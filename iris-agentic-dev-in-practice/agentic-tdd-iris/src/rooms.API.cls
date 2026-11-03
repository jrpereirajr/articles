/// REST endpoints for the room scheduler.
Class rooms.API Extends %CSP.REST
{

/// Without this, %request.Content arrives as a raw binary stream and JSON
/// parsing silently yields an empty object (same parameter %Api.Atelier sets).
Parameter CONVERTINPUTSTREAM = 1;

XData UrlMap
{
<Routes>
<Route Url="/bookings" Method="POST" Call="CreateBooking"/>
<Route Url="/availability" Method="GET" Call="ListBookings"/>
</Routes>
}

/// POST /bookings  {"room":"atlantis","start":"09:00","end":"10:00","owner":"jose"}
/// -> 200 {"id":1}  |  409 {"error":"room busy"}
ClassMethod CreateBooking() As %Status
{
	; The gateway hands the request body over as a %CSP.Stream with the pointer
	; at EOF — rewind, read it into a string, then parse with the {} literal
	; (the documented %CSP.REST pattern; a %New()-created %DynamicObject
	; parses as an empty object).
	Do %request.Content.Rewind()
	Set bodyStr = %request.Content.Read(%request.Content.Size)
	Set parseFailed = 0
	Try {
		Set body = {}.%FromJSON(bodyStr)
	} Catch {
		Set parseFailed = 1
	}
	If parseFailed {
		Set %response.Status = 400
		Write {"error": ("invalid JSON body")}.%ToJSON()
		Quit $$$OK
	}
	Set id = ##class(rooms.Booking).Book(body.room, body.start, body.end, body.owner, .reason)
	If id = "" {
		Set %response.Status = 409
		Write {"error": ($Get(reason))}.%ToJSON()
		Quit $$$OK
	}
	Write {"id": (id)}.%ToJSON()
	Quit $$$OK
}

/// GET /availability?room=atlantis
/// -> {"room":"atlantis","booked":[{"start":"09:00","end":"10:00"}, ...]}
ClassMethod ListBookings() As %Status
{
	Set room = %request.Get("room")
	Set booked = []
	Set stmt = ##class(%SQL.Statement).%New()
	Set sc = stmt.%Prepare("SELECT StartTime, EndTime FROM rooms.Booking WHERE Room = ? ORDER BY StartTime")
	If $System.Status.IsError(sc) {
		Set %response.Status = 500
		Quit $$$OK
	}
	Set rs = stmt.%Execute(room)
	While rs.%Next() {
		Do booked.%Push({"start": (rs.StartTime), "end": (rs.EndTime)})
	}
	Write {"room": (room), "booked": (booked)}.%ToJSON()
	Quit $$$OK
}

}
