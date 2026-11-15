--[[

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@meta

---Fills gaps in the CfxLua library types. Declarations here MUST match the FiveM runtime.

---DrawMarker without a texture takes nil for both texture names. An empty string crashes the game.
---@param type integer
---@param posX number
---@param posY number
---@param posZ number
---@param dirX number
---@param dirY number
---@param dirZ number
---@param rotX number
---@param rotY number
---@param rotZ number
---@param scaleX number
---@param scaleY number
---@param scaleZ number
---@param red integer
---@param green integer
---@param blue integer
---@param alpha integer
---@param bobUpAndDown boolean
---@param faceCamera boolean
---@param rotationOrder integer
---@param rotate boolean
---@param textureDict? string
---@param textureName? string
---@param drawOnEnts boolean
function DrawMarker(type, posX, posY, posZ, dirX, dirY, dirZ, rotX, rotY, rotZ, scaleX, scaleY, scaleZ, red, green, blue, alpha, bobUpAndDown, faceCamera, rotationOrder, rotate, textureDict, textureName, drawOnEnts) end
