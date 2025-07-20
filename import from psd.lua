-- Import PSD to Aseprite
-- This script imports PSD files exported by "Export as psd.lua" back to Aseprite
-- Based on the subset of PSD format used by the export script
-- Supports both RGB (3 channels) and RGBA (4 channels) PSD files
-- Fully supports PSD group/folder structures with proper Layer.isGroup mapping

-- ==============================
-- UTF-8 Safety Functions
-- ==============================

---Convert UTF-16BE to UTF-8
---@param utf16 string UTF-16BE encoded string
---@return string utf8 UTF-8 encoded string
local function utf16beToUtf8(utf16)
    -- Cache global variables to local.
    local strchar <const> = string.char
    local strsub <const> = string.sub
    local strunpack <const> = string.unpack

    local lenUtf8 = 0
    local utf8 <const> = {}
    local lenUtf16 <const> = #utf16
    -- TODO: Use while loop.
    for i = 1, lenUtf16, 2 do
        if i + 1 <= lenUtf16 then
            local code <const> = strunpack(">I2", strsub(utf16, i, i + 1))
            if code >= 0xD800 and code <= 0xDFFF then
                -- Surrogate pair handling (rare in PSD, skip for now)
                lenUtf8 = lenUtf8 + 1
                utf8[lenUtf8] = "?"
            else
                -- Convert Unicode code point to UTF-8
                if code <= 0x7F then
                    lenUtf8 = lenUtf8 + 1
                    utf8[lenUtf8] = strchar(code)
                elseif code <= 0x7FF then
                    local b1 <const> = 0xC0 + code // 64
                    local b2 <const> = 0x80 + code % 64

                    lenUtf8 = lenUtf8 + 1
                    utf8[lenUtf8] = strchar(b1, b2)
                elseif code <= 0xFFFF then
                    local b1 <const> = 0xE0 + code // 4096
                    local b2 <const> = 0x80 + (code % 4096) // 64
                    local b3 <const> = 0x80 + code % 64

                    lenUtf8 = lenUtf8 + 1
                    utf8[lenUtf8] = strchar(b1, b2, b3)
                else
                    lenUtf8 = lenUtf8 + 1
                    utf8[lenUtf8] = "?"
                end -- End code inner bit range check.
            end     -- End Code outer bit range check.
        end         -- End next index less than length.
    end             -- End utf16 loop.

    return table.concat(utf8)
end

---Ensure string is safe UTF-8 (fallback for corrupted strings)
---@param str string
---@return string
local function safeUtf8(str)
    if not str or str == "" then return "" end

    local strbyte <const> = string.byte
    -- local strchar <const> = string.char
    -- local strsub <const> = string.sub

    -- Simple UTF-8 validation: check for invalid byte sequences
    -- local result = {}
    local i = 1
    local valid = true
    local lenStr <const> = #str
    -- local lenResult = 0

    while i <= lenStr do
        local b1 <const> = strbyte(str, i)

        if b1 <= 0x7F then
            -- ASCII character (0xxxxxxx)
            -- lenResult = lenResult + 1
            -- result[lenResult] = strchar(b1)
            i = i + 1
        elseif b1 >= 0xC2
            and b1 <= 0xDF then
            -- 2-byte sequence (110xxxxx 10xxxxxx)
            if i + 1 <= lenStr then
                local b2 <const> = strbyte(str, i + 1)
                if b2 >= 0x80
                    and b2 <= 0xBF then
                    -- lenResult = lenResult + 1
                    -- result[lenResult] = strsub(str, i, i + 1)
                    i = i + 2
                else
                    valid = false
                    break
                end
            else
                valid = false
                break
            end
        elseif b1 >= 0xE0 and b1 <= 0xEF then
            -- 3-byte sequence (1110xxxx 10xxxxxx 10xxxxxx)
            if i + 2 <= lenStr then
                local b2 <const> = strbyte(str, i + 1)
                local b3 <const> = strbyte(str, i + 2)
                if b2 >= 0x80
                    and b2 <= 0xBF
                    and b3 >= 0x80
                    and b3 <= 0xBF then
                    -- lenResult = lenResult + 1
                    -- result[lenResult] = strsub(str, i, i + 2)
                    i = i + 3
                else
                    valid = false
                    break
                end
            else
                valid = false
                break
            end
        elseif b1 >= 0xF0 and b1 <= 0xF4 then
            -- 4-byte sequence (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
            if i + 3 <= lenStr then
                local b2 <const> = strbyte(str, i + 1)
                local b3 <const> = strbyte(str, i + 2)
                local b4 <const> = strbyte(str, i + 3)
                if b2 >= 0x80
                    and b2 <= 0xBF
                    and b3 >= 0x80
                    and b3 <= 0xBF
                    and b4 >= 0x80
                    and b4 <= 0xBF then
                    -- lenResult = lenResult + 1
                    -- result[lenResult] = strsub(str, i, i + 3)
                    i = i + 4
                else
                    valid = false
                    break
                end
            else
                valid = false
                break
            end
        else
            -- Invalid byte
            valid = false
            break
        end
    end

    if valid then
        return str
    else
        -- Replace all non-ASCII bytes with underscore to prevent crashes
        return (string.gsub(str, "[\128-\255]", "_"))
    end
end



-- ==============================
-- Helper Functions for Binary Reading
-- ==============================

---Read unsigned 16-bit big-endian integer
---@param file file*
---@return integer
local function readU16BE(file)
    return string.unpack(">I2", file:read(2))
end

---Read signed 16-bit big-endian integer
---@param file file*
---@return integer
local function readI16BE(file)
    return string.unpack(">i2", file:read(2))
end

---Read unsigned 32-bit big-endian integer
---@param file file*
---@return integer
local function readU32BE(file)
    return string.unpack(">I4", file:read(4))
end

---Read signed 32-bit big-endian integer
---@param file file*
---@return integer
local function readI32BE(file)
    return string.unpack(">i4", file:read(4))
end

---Read unsigned 8-bit integer
---@param file file*
---@return integer
local function readU8(file)
    return string.unpack("B", file:read(1))
end

---Read Pascal string (length-prefixed, padded to 4-byte boundary)
---@param file file*
---@return string
local function readPascalString(file)
    local len = readU8(file)
    local str = ""
    if len > 0 then
        str = file:read(len)
    end
    local padBytes = (4 - ((len + 1) % 4)) % 4
    if padBytes > 0 then
        _ = file:read(padBytes)
    end
    return str
end

-- ==============================
-- PackBits Decoder
-- ==============================

---Decode PackBits compressed data
---@param data string
---@return string
local function unpackBits(data)
    ---@type string[]
    local result <const> = {}
    local lenData <const> = #data

    local i = 1
    while i <= lenData do
        local n = string.byte(data, i)
        i = i + 1

        if n <= 127 then
            -- Literal run: copy next n+1 bytes
            local count = n + 1
            if i + count - 1 <= lenData then
                result[#result + 1] = data:sub(i, i + count - 1)
                i = i + count
            else
                break
            end
        elseif n >= 129 then
            -- Replicate run: repeat next byte (257-n) times
            if i <= lenData then
                local byte = data:sub(i, i)
                local count = 257 - n
                result[#result + 1] = byte:rep(count)
                i = i + 1
            else
                break
            end
        end
        -- n == 128: NOP (do nothing)
    end

    return table.concat(result)
end

-- ==============================
-- Blend Mode Mapping
-- ==============================

local blendModeMap <const> = {
    ["norm"] = BlendMode.NORMAL,
    ["mul "] = BlendMode.MULTIPLY,
    ["scrn"] = BlendMode.SCREEN,
    ["over"] = BlendMode.OVERLAY,
    ["dark"] = BlendMode.DARKEN,
    ["lite"] = BlendMode.LIGHTEN,
    ["div "] = BlendMode.COLOR_DODGE,
    ["idiv"] = BlendMode.COLOR_BURN,
    ["hLit"] = BlendMode.HARD_LIGHT,
    ["sLit"] = BlendMode.SOFT_LIGHT,
    ["diff"] = BlendMode.DIFFERENCE,
    ["smud"] = BlendMode.EXCLUSION,
    ["hue "] = BlendMode.HSL_HUE,
    ["sat "] = BlendMode.HSL_SATURATION,
    ["colr"] = BlendMode.HSL_COLOR,
    ["lum "] = BlendMode.HSL_LUMINOSITY,
    ["lddg"] = BlendMode.ADDITION,
    ["fsub"] = BlendMode.SUBTRACT,
    ["fdiv"] = BlendMode.DIVIDE,
}

-- ==============================
-- Layer Data Structures
-- ==============================

---@class LayerInfo
---@field name string
---@field bounds {top: integer, left: integer, bottom: integer, right: integer}
---@field channels {id: integer, size: integer}[]
---@field blendMode string
---@field opacity integer
---@field visible boolean
---@field isGroup boolean
---@field groupType integer|nil -- 0=other, 1=open folder, 2=closed folder, 3=bounding divider
---@field channelData string[]

-- ==============================
-- PSD Import Function
-- ==============================

---Import PSD file and create Aseprite sprite
---@param filename string
---@param trimImageAlpha boolean
---@return boolean success
---@return string|nil errorMessage
local function importFromPsd(filename, trimImageAlpha)
    local file = io.open(filename, "rb")
    if not file then
        return false, "Failed to open PSD file: " .. filename
    end

    -- ==============================
    -- File Header Section
    -- ==============================

    -- Check signature
    local signature = file:read(4)
    if signature ~= "8BPS" then
        file:close()
        return false, "Not a valid PSD file (invalid signature)"
    end

    -- Check version
    local version = readU16BE(file)
    if version ~= 1 then
        file:close()
        return false, "Unsupported PSD version: " .. version
    end

    -- Skip reserved bytes
    _ = file:read(6)

    -- Read channels count
    local channels = readU16BE(file)
    if channels ~= 3 and channels ~= 4 then
        file:close()
        return false, "Unsupported channel count: " .. channels .. " (only 3 or 4 allowed)"
    end
    local hasAlpha = (channels == 4)

    -- Read dimensions
    local height = readU32BE(file)
    local width = readU32BE(file)

    -- Check depth
    local depth = readU16BE(file)
    if depth ~= 8 then
        file:close()
        return false, "Unsupported bit depth: " .. depth .. " (expected 8)"
    end

    -- Check color mode
    local psdColorMode <const> = readU16BE(file)
    if psdColorMode ~= 3 then
        file:close()
        return false, "Unsupported color mode: " .. psdColorMode .. " (expected 3 for RGB)"
    end

    -- ==============================
    -- Color Mode Data Section
    -- ==============================

    local colorModeDataLength = readU32BE(file)
    if colorModeDataLength > 0 then
        _ = file:read(colorModeDataLength)
    end

    -- ==============================
    -- Image Resources Section
    -- ==============================

    local imageResourcesLength = readU32BE(file)
    if imageResourcesLength > 0 then
        _ = file:read(imageResourcesLength)
    end

    -- ==============================
    -- Layer and Mask Information Section
    -- ==============================

    local layerAndMaskLength = readU32BE(file)
    local layerAndMaskEnd = file:seek("cur") + layerAndMaskLength

    local layerInfoLength = readU32BE(file)
    local layerCount = readI16BE(file)

    if layerCount < 0 then
        layerCount = -layerCount -- Absolute value for layer count
    end

    -- Read layer records
    local layers = {} ---@type LayerInfo[]

    for i = 1, layerCount do
        local layer = {}

        -- Read bounds
        layer.bounds = {
            top = readI32BE(file),
            left = readI32BE(file),
            bottom = readI32BE(file),
            right = readI32BE(file)
        }

        -- Read channel count and channel info
        local channelCount = readU16BE(file)
        layer.channels = {}

        for j = 1, channelCount do
            local channelId = readI16BE(file)
            local channelSize = readU32BE(file)
            layer.channels[j] = { id = channelId, size = channelSize }
        end

        -- Read blend mode signature
        local blendSig = file:read(4)
        if blendSig ~= "8BIM" then
            file:close()
            return false, "Invalid blend mode signature in layer " .. i
        end

        -- Read blend mode
        layer.blendMode = file:read(4)

        -- Read opacity
        layer.opacity = readU8(file)

        -- Read clipping (skip)
        readU8(file)

        -- Read flags
        local flags = readU8(file)
        layer.visible = (flags & 2) == 0 -- Bit 1: visibility (0 = visible)

        -- Read filler
        readU8(file)

        -- Read extra data field length
        local extraLength = readU32BE(file)
        local extraStart = file:seek("cur")

        -- Skip layer mask (always 0 in our export)
        local maskLength = readU32BE(file)
        if maskLength > 0 then
            _ = file:read(maskLength)
        end

        -- Skip blending ranges (always 0 in our export)
        local blendingRangesLength = readU32BE(file)
        if blendingRangesLength > 0 then
            _ = file:read(blendingRangesLength)
        end

        -- Read layer name
        layer.name = readPascalString(file)

        -- Check for additional layer information (lsct)
        layer.isGroup = false
        layer.groupType = nil

        ----------------------------------------------------------------
        -- Scan entire additional information area (previous single-if → while-loop)
        ----------------------------------------------------------------
        local curPos = file:seek("cur")
        local processed = curPos - extraStart
        local remaining = extraLength - processed

        while remaining >= 12 do                 -- Continue if header is larger than 12 bytes
            local addSig = file:read(4)          -- "8BIM"
            local addKey = file:read(4)          -- "luni" / "lsct" etc.
            local addLen = readU32BE(file)       -- payload length
            local padded = addLen + (addLen % 2) -- 2-byte even padding
            remaining = remaining - (12 + padded)

            if addSig ~= "8BIM" then -- Unexpected signature
                file:seek("cur", -8) -- Rewind and skip remaining
                if remaining > 0 then
                    _ = file:read(remaining)
                end
                break
            end

            if addKey == "lsct" and addLen >= 4 then -- ★ Folder information found
                layer.groupType = readU32BE(file)    -- 0/1/2=opener, 3=closer
                layer.isGroup = true
                if padded > 4 then                   -- Skip remaining
                    _ = file:read(padded - 4)
                end
            elseif addKey == "luni" and addLen >= 4 then -- ★ Unicode layer name found
                local count = readU32BE(file)            -- UTF-16 code unit count
                local bytesToRead = count * 2
                if bytesToRead > 0 and bytesToRead <= addLen - 4 then
                    local utf16 = file:read(bytesToRead) -- Read UTF-16BE data
                    layer.name = utf16beToUtf8(utf16)    -- Convert to UTF-8
                    if padded > 4 + bytesToRead then     -- Skip remaining padding
                        _ = file:read(padded - 4 - bytesToRead)
                    end
                else
                    -- Invalid data, skip entire block
                    if padded > 4 then
                        _ = file:read(padded - 4)
                    end
                end
            else
                -- Uninterested block: skip entire payload
                if padded > 0 then _ = file:read(padded) end
            end
        end

        layers[i] = layer
    end

    -- Read channel image data
    for i = 1, layerCount do
        local layer <const> = layers[i]
        layer.channelData = {}

        -- Create channel data mapping by channel ID
        local channelDataByID = {}

        for j = 1, #layer.channels do
            local channelInfo = layer.channels[j]
            local channelData = file:read(channelInfo.size)

            local decodedData = ""
            if #channelData >= 2 then
                local compression = string.unpack(">I2", channelData:sub(1, 2))
                if compression == 1 then
                    -- RLE compression
                    local imageHeight = layer.bounds.bottom - layer.bounds.top
                    if imageHeight > 0 then
                        local rowSizeTableSize = imageHeight * 2
                        if #channelData >= 2 + rowSizeTableSize then
                            local rowData = channelData:sub(3 + rowSizeTableSize)

                            -- Remove padding if present (odd-length rows get 0x80 padding)
                            if #rowData > 0 and string.byte(rowData, #rowData) == 0x80 and #rowData % 2 == 0 then
                                rowData = rowData:sub(1, #rowData - 1)
                            end

                            decodedData = unpackBits(rowData)
                        end
                    end
                else
                    decodedData = channelData:sub(3)
                end
            end

            -- Map channel data by ID: 0 = R, 1 = G, 2 = B, -1 = A
            channelDataByID[channelInfo.id] = decodedData
        end

        -- Store in standard order: R, G, B, A
        layer.channelData[1] = channelDataByID[0] or ""                             -- Red
        layer.channelData[2] = channelDataByID[1] or ""                             -- Green
        layer.channelData[3] = channelDataByID[2] or ""                             -- Blue
        layer.channelData[4] = channelDataByID[-1] or channelDataByID[0xFFFF] or "" -- Alpha
    end

    file:close()

    -- ==============================
    -- Create Aseprite Sprite
    -- ==============================

    -- Cache global methods used in loop to locals.
    local strbyte <const> = string.byte
    local rgbaCompose <const> = app.pixelColor.rgba
    local tinsert <const> = table.insert
    local tremove <const> = table.remove
    local strchar <const> = string.char
    local strrep <const> = string.rep

    local aseColorMode <const> = ColorMode.RGB
    local aseAlphaIndex <const> = 0
    local aseColorSpace <const> = ColorSpace { sRGB = true }

    local spriteSpec <const> = ImageSpec {
        width = width,
        height = height,
        colorMode = aseColorMode,
        transparentColor = aseAlphaIndex,
    }
    spriteSpec.colorSpace = aseColorSpace

    -- TODO: Preserve fore and background color before creating sprite.
    local sprite <const> = Sprite(spriteSpec)
    sprite.filename = app.fs.fileName(filename)
    local defaultLayer <const> = sprite.layers[1]

    -- Process layers in reverse order to match PSD layer stack (Top→Bottom becomes Bottom→Top)
    local groupStack = {} ---@type Layer[]

    -- TODO: Use while loop.
    for i = layerCount, 1, -1 do
        local layerInfo <const> = layers[i]

        ------------------------------------------------------------
        -- (1) Overall structure for layer/group creation
        ------------------------------------------------------------
        if layerInfo.isGroup then
            ----------------------------------------------------------
            -- A. Opener: type 0·1·2  →  Create folder and continue
            ----------------------------------------------------------
            if layerInfo.groupType == 0 or layerInfo.groupType == 1
                or layerInfo.groupType == 2 then
                local grp <const> = sprite:newGroup()
                grp.name = safeUtf8(layerInfo.name)
                grp.isVisible = layerInfo.visible
                grp.isExpanded = (layerInfo.groupType ~= 2)

                -- Assign parent folder
                if #groupStack > 0 then
                    grp.parent = groupStack[#groupStack]
                end
                grp.stackIndex = 1       -- Move to bottom
                tinsert(groupStack, grp) -- push

                ------------------------- Important -------------------------
                goto nextRecord -- Must end here to prevent double creation
                --------------------------------------------------------
                ----------------------------------------------------------
                -- B. Closer: type 3  →  Close folder and continue (no layer)
                ----------------------------------------------------------
            elseif layerInfo.groupType == 3 then
                if #groupStack > 0 then
                    tremove(groupStack)
                end
                goto nextRecord
            end
        end

        ------------------------------------------------------------
        -- (2) Regular layer processing (isGroup == false) ---------
        ------------------------------------------------------------
        local lay <const> = sprite:newLayer()
        lay.name = safeUtf8(layerInfo.name)
        lay.isVisible = layerInfo.visible
        lay.opacity = layerInfo.opacity

        if blendModeMap[layerInfo.blendMode] then
            lay.blendMode = blendModeMap[layerInfo.blendMode]
        end

        if #groupStack > 0 then
            lay.parent = groupStack[#groupStack]
        end
        lay.stackIndex = 1

        -- Create image if layer has content
        -- TODO: Look into this being different from
        -- Aseprite convention of right = width - 1,
        -- and so width = 1 + right - left .
        local wLayer <const> = layerInfo.bounds.right - layerInfo.bounds.left
        local hLayer <const> = layerInfo.bounds.bottom - layerInfo.bounds.top

        if wLayer > 0
            and hLayer > 0
            and #layerInfo.channelData >= 4 then
            local imageSpec <const> = ImageSpec {
                width = wLayer,
                height = hLayer,
                colorMode = aseColorMode,
                transparentColor = aseAlphaIndex,
            }
            imageSpec.colorSpace = aseColorSpace
            local image <const> = Image(imageSpec)

            -- Decode channel data
            local rData <const> = layerInfo.channelData[1] or ""
            local gData <const> = layerInfo.channelData[2] or ""
            local bData <const> = layerInfo.channelData[3] or ""
            local aData = layerInfo.channelData[4] -- may be nil

            -- If no alpha channel, create opaque alpha data
            local expectedSize <const> = wLayer * hLayer
            local opaque <const> = strrep(strchar(255), expectedSize)
            if not aData or #aData == 0 then
                aData = opaque
            end

            for y = 0, hLayer - 1 do
                for x = 0, wLayer - 1 do
                    local pixelIndex = y * wLayer + x + 1

                    local r = 0
                    local g = 0
                    local b = 0
                    local a = 255

                    if pixelIndex <= #rData then
                        r = strbyte(rData, pixelIndex)
                    end
                    if pixelIndex <= #gData then
                        g = strbyte(gData, pixelIndex)
                    end
                    if pixelIndex <= #bData then
                        b = strbyte(bData, pixelIndex)
                    end
                    if pixelIndex <= #aData then
                        a = strbyte(aData, pixelIndex)
                    end

                    -- TODO: This entire loop could be more efficient.
                    local abgr32 <const> = rgbaCompose(r, g, b, a)
                    image:drawPixel(x, y, abgr32)
                end -- Pixel loop x
            end     -- Pixel loop y

            local layerBounds <const> = layerInfo.bounds
            local xPos = layerBounds.left
            local yPos = layerBounds.top
            local trimmedImage = image

            if trimImageAlpha then
                local trimRect <const> = trimmedImage:shrinkBounds(aseAlphaIndex)
                local wTrimRect <const> = trimRect.width
                local hTrimRect <const> = trimRect.height

                local rectIsValid <const> = wTrimRect > 0
                    and hTrimRect > 0
                if rectIsValid then
                    local xtlTrim <const> = trimRect.x
                    local ytlTrim <const> = trimRect.y

                    local trimmedSpec <const> = ImageSpec {
                        width = wTrimRect,
                        height = hTrimRect,
                        colorMode = aseColorMode,
                        transparentColor = aseAlphaIndex,
                    }
                    imageSpec.colorSpace = aseColorSpace

                    trimmedImage = Image(trimmedSpec)
                    trimmedImage:drawImage(
                        image,
                        Point(-xtlTrim, -ytlTrim),
                        255,
                        BlendMode.SRC)

                    xPos = xPos + xtlTrim
                    yPos = yPos + ytlTrim
                end -- End trim rectangle is valid.
            end     -- End use image trimming.

            local cel <const> = sprite:newCel(
                lay,
                1, -- TODO: This should be a frame index, not a magic number.
                trimmedImage,
                Point(xPos, yPos))
        end

        -- TODO: Remove goto statements.
        ::nextRecord::
        -- ↓ continue for-loop
    end -- End loop.

    -- Remove default layer if other layers have been created.
    if #sprite.layers > 1 then
        sprite:deleteLayer(defaultLayer)
    end

    return true, nil
end

-- ==============================
-- UI and Entry Point
-- ==============================

if app.apiVersion < 1 then
    if app.isUIAvailable then
        app.alert({
            title = "Import Failed",
            text = "This script requires Aseprite v1.2.10-beta3 or above.",
            buttons = "OK"
        })
    else
        io.stderr:write("Import failed: this script requires Aseprite v1.2.10-beta3 or above.")
    end
    return
end

local function showImportDialog()
    local dlg <const> = Dialog {
        title = "PSD Import"
    }

    dlg:file {
        id = "filename",
        label = "Open:",
        filetypes = { "psd" },
        basepath = app.fs.userDocsPath,
        focus = true,
    }

    dlg:newrow { wait = false }

    dlg:button {
        id = "ok",
        text = "&OK",
        focus = false,
        onclick = function()
            local filename = dlg.data.filename --[[@as string]]
            if filename and filename ~= "" then
                local success <const>,
                errorMessage <const> = importFromPsd(filename, true)
                if success then
                    app.command.ColorQuantization {
                        algorithm = 1,
                        maxColors = 256,
                        ui = false,
                        withAlpha = true,
                    }
                else
                    app.alert({
                        title = "Import Failed",
                        text = {
                            "An error occurred while importing the PSD file:",
                            (errorMessage or "Unknown error"),
                        },
                        buttons = "OK"
                    })
                end
            end
        end
    }

    dlg:button {
        id = "cancel",
        text = "&Cancel",
        focus = false,
    }

    dlg:show {
        wait = false,
        autoscrollbars = false
    }
end

local function getOptionsFromCLI()
    local filename = nil

    for key, value in pairs(app.params) do
        local lcKey <const> = string.lower(key)
        if lcKey == "filename"
            or lcKey == "file"
            or lcKey == "f" then
            filename = value
        end
    end

    return filename
end

if app.isUIAvailable then
    showImportDialog()
else
    local filename <const> = getOptionsFromCLI()
    if filename then
        local success <const>,
        errorMessage <const> = importFromPsd(filename, true)
        if success then
            print("PSD file imported successfully: " .. filename)
        else
            io.stderr:write("Import failed: " .. (errorMessage or "Unknown error"))
        end
    else
        io.stderr:write("Usage: aseprite -b -script 'import from psd.lua' --filename=file.psd")
    end
end