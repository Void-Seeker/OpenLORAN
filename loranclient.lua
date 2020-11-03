PORT_LORAN = 8192

local loranclient = {}
local vector = {}
local _vector = {
	add = function( self, o )
		return vector.new(
			self.x + o.x,
			self.y + o.y,
			self.z + o.z
		)
	end,
	sub = function( self, o )
		return vector.new(
			self.x - o.x,
			self.y - o.y,
			self.z - o.z
		)
	end,
	mul = function( self, m )
		return vector.new(
			self.x * m,
			self.y * m,
			self.z * m
		)
	end,
	dot = function( self, o )
		return self.x*o.x + self.y*o.y + self.z*o.z
	end,
	cross = function( self, o )
		return vector.new(
			self.y*o.z - self.z*o.y,
			self.z*o.x - self.x*o.z,
			self.x*o.y - self.y*o.x
		)
	end,
	length = function( self )
		return math.sqrt( self.x*self.x + self.y*self.y + self.z*self.z )
	end,
	normalize = function( self )
		return self:mul( 1 / self:length() )
	end,
	round = function( self, nTolerance )
	    nTolerance = nTolerance or 1.0
		return vector.new(
			math.floor( (self.x + (nTolerance * 0.5)) / nTolerance ) * nTolerance,
			math.floor( (self.y + (nTolerance * 0.5)) / nTolerance ) * nTolerance,
			math.floor( (self.z + (nTolerance * 0.5)) / nTolerance ) * nTolerance
		)
	end,
	tostring = function( self )
		return self.x..","..self.y..","..self.z
	end,
}

local vmetatable = {
	__index = _vector,
	__add = _vector.add,
	__sub = _vector.sub,
	__mul = _vector.mul,
	__unm = function( v ) return v:mul(-1) end,
	__tostring = _vector.tostring,
}

function vector.new( x, y, z )
	local v = {
		x = x or 0,
		y = y or 0,
		z = z or 0
	}
	setmetatable( v, vmetatable )
	return v
end

local component = require "component"
local event = require "event"
local term = require "term"

local function trilaterate( A, B, C )
	local a2b = B.position - A.position
	local a2c = C.position - A.position
		
	if math.abs( a2b:normalize():dot( a2c:normalize() ) ) > 0.999 then
		return nil
	end
	
	local d = a2b:length()
	local ex = a2b:normalize( )
	local i = ex:dot( a2c )
	local ey = (a2c - (ex * i)):normalize()
	local j = ey:dot( a2c )
	local ez = ex:cross( ey )

	local r1 = A.distance
	local r2 = B.distance
	local r3 = C.distance
		
	local x = (r1*r1 - r2*r2 + d*d) / (2*d)
	local y = (r1*r1 - r3*r3 - x*x + (x-i)*(x-i) + j*j) / (2*j)
		
	local result = A.position + (ex * x) + (ey * y)

	local zSquared = r1*r1 - x*x - y*y
	if zSquared > 0 then
		local z = math.sqrt( zSquared )
		local result1 = result + (ez * z)
		local result2 = result - (ez * z)
		
		local rounded1, rounded2 = result1:round( 0.01 ), result2:round( 0.01 )
		if rounded1.x ~= rounded2.x or rounded1.y ~= rounded2.y or rounded1.z ~= rounded2.z then
			return rounded1, rounded2
		else
			return rounded1
		end
	end
	return result:round( 0.01 )
end

local function narrow( p1, p2, fix )
	local dist1 = math.abs( (p1 - fix.position):length() - fix.distance )
	local dist2 = math.abs( (p2 - fix.position):length() - fix.distance )
	
	if math.abs(dist1 - dist2) < 0.01 then
		return p1, p2
	elseif dist1 < dist2 then
		return p1:round( 0.01 )
	else
		return p2:round( 0.01 )
	end
end
local function poll(timeout, modem, debug )
	modem = modem or component.modem
	timeout = timeout or 2

	if modem == nil then
		if debug then
			print( "No wireless modem attached" )
		end
		return nil
	end
	
	-- Open port
	local localport = math.random(1,PORT_LORAN-1)
	local openedPort = false
	if not modem.isOpen( localport ) then
		modem.open( localport )
		openedPort = true
	end
	
	local stations = {}
	-- Send poll request to listening LORAN basestations
	modem.broadcast( PORT_LORAN, "LORAN", localport, "POLL" )
	while true do
		local e = {event.pull(timeout)}
		if e[1] == "modem_message" then
			-- We received a message from a modem
			local address, from, port, distance, header = table.unpack(e,2,6)
			local message = {table.unpack(e,7,#e)}
			if address == modem.address and port == localport and header == "LORAN" then
				-- Received the correct message from the correct modem: use it to determine position
				if #message == 5 then
					local fix = { sid = message[1], position = vector.new( message[2], message[3], message[4] ), distance = distance, datetime = message[5] }
					if debug then
						print( "Detected basestation " .. fix.sid .. "( " ..fix.position.x..", "..fix.position.y..", "..fix.position.z .. " ) " .. fix.distance .. " meters away." )
					end
					table.insert(stations, fix)
				end
			end
		elseif e[1] == nil then
			break
		end 
	end
	-- Close the port, if we opened one
	if openedPort then
		modem.close( localport )
	end	
	return stations
end

function loranclient.stations(timeout, modem, debug)
	return poll(timeout, modem, debug)
end

function loranclient.locate( timeout, modem, debug )
	
	stations = poll(timeout, modem, debug)
	local pos1, pos2 = nil, nil
	for i = 1, #stations do
		if stations[i].distance == 0 then
			pos1, pos2 = stations[i].position, nil
		else
            if i >= 3 then
                if not pos1 then
                    pos1, pos2 = trilaterate( stations[1], stations[2], stations[i] )
                else
                    pos1, pos2 = narrow( pos1, pos2, stations[i] )
                end
            end
        end
		if pos1 and not pos2 then
			break
		end
	end
	
	-- Return the response
	if pos1 and pos2 then
		if debug then
			print( "Ambiguous position" )
			print( "Could be "..pos1.x..","..pos1.y..","..pos1.z.." or "..pos2.x..","..pos2.y..","..pos2.z )
		end
		return nil, nil, nil, "AMBIGUOUS_POSITION"
	elseif pos1 then
		if debug then
			print( "Position is "..pos1.x..","..pos1.y..","..pos1.z )
		end
		return pos1.x, pos1.y, pos1.z, "OK"
	else
		if debug then
			print( "Could not determine position" )
		end
		return nil, nil, nil, "NO_FIX"
	end
end

return loranclient
