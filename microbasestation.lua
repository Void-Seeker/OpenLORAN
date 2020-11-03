local PORT_LORAN = 8192
-- ID(number or alias) and coordinates of the basestation, must be specified before flashing
-- basestation EEPROM
local sid = 0
local x,y,z = 0,0,0
--These definitions allow using microbasestation from OpenOS
local component = component or require "component"
local computer = computer or require "computer"
local modem = component.proxy(component.list("modem")())
local colorful_lamp, chunkloader
local timeout
-- If colorful lamp from Computronics is nearby, use it to indicate
-- status of the system
function indicate(color)
  if colorfullamp then
    colorful_lamp.setLampColor(color)
    return true
  end
  return false
end
function serializeTable(val, name)
    local tmp = ""
    if name then tmp = tmp .. name .. "=" end
    if type(val) == "table" then
        tmp = tmp .. "{"
        for k, v in pairs(val) do
            tmp = tmp .. serializeTable(v, k) .. ","
        end
        tmp = tmp .. "}"
    elseif type(val) == "number" then
        if val ~= val then
          tmp = tmp .. "0/0"
          elseif val == math.huge then
          tmp = tmp ..  "math.huge"
          elseif val == -math.huge then
          tmp = tmp .. "-math.huge"
          else
          tmp = tmp .. tostring(val)
        end
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end
    return tmp
end
if component.list("colorful_lamp")() then
  colorful_lamp = component.proxy(component.list("colorful_lamp")())
  timeout = 1
end
-- If chunkloader is present, use it.
if component.list("chunkloader")() then
  chunkloader = component.proxy(component.list("chunkloader")())
  chunkloader.setActive(true)
end
if modem == nil then
  indicate(31744)
  return
end
if not modem.isOpen(PORT_LORAN) then
  modem.open(PORT_LORAN)
end
local nServed = 0
local telemetry = { sid = sid, x = x, y = y, z = z, freeMemory = computer.freeMemory(),
  totalMemory = computer.totalMemory(), energy = computer.energy(), maxEnergy = computer.maxEnergy(),
  uptime = computer.uptime(), address = modem.address, queriesServed = nServed }
local heartbeat = false
while true do
  if colorful_lamp then
    if not heartbeat then
      colorful_lamp.setLampColor(992)
	  heartbeat = true
    else
      colorful_lamp.setLampColor(0)
	  heartbeat = false
    end
  end
  local e = { computer.pullSignal(timeout) }
  if e[1] == "modem_message" then
  indicate(63)
    local address, from, port, distance, header = table.unpack(e,2,6)
    local message = {table.unpack(e,7,#e)}
    if address == modem.address and port == PORT_LORAN then
        local from_port = message[1]
        if header == "LORAN" and message[2] == "POLL" then
          modem.send( from, from_port, "LORAN", sid, x, y, z, os.time() )
          nServed = nServed + 1
        elseif header == "LORAN_TELEMETRY" and message[2] == "POLL" then
          telemetry = { sid = sid, x = x, y = y, z = z, freeMemory = computer.freeMemory(),
            totalMemory = computer.totalMemory(), energy = computer.energy(), maxEnergy = computer.maxEnergy(),
            uptime = computer.uptime(), address = modem.address, queriesServed = nServed }
          modem.send( from, from_port, "LORAN_TELEMETRY", serializeTable(telemetry) )
        end
    end
  end
end
modem.close(PORT_LORAN)