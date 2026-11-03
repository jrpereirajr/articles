/// A room reservation. The persistent store behind the scheduler.
Class rooms.Booking Extends %Persistent
{

Property Room As %String(MAXLEN = 32);

/// HH:MM, the day is implicit (single-day calendar).
Property StartTime As %String(MAXLEN = 5);

/// HH:MM.
Property EndTime As %String(MAXLEN = 5);

Property Owner As %String(MAXLEN = 64);

Index RoomIdx On Room;

/// True when no saved booking for the room overlaps the requested window.
ClassMethod CanBook(room As %String, startTime As %String, endTime As %String) As %Boolean
{
	Set stmt = ##class(%SQL.Statement).%New()
	Set sc = stmt.%Prepare("SELECT StartTime, EndTime FROM rooms.Booking WHERE Room = ?")
	If $System.Status.IsError(sc) {
		Quit 0
	}
	Set rs = stmt.%Execute(room)
	Set conflict = 0
	While rs.%Next() {
		If ##class(rooms.Scheduler).Overlaps(startTime, endTime, rs.StartTime, rs.EndTime) {
			Set conflict = 1
			Quit
		}
	}
	Quit 'conflict
}

/// Creates a booking after checking the room's calendar. Returns the new id,
/// or "" with the reason in pReason.
ClassMethod Book(room As %String, startTime As %String, endTime As %String, owner As %String, Output pReason As %String = "") As %String
{
	If '..CanBook(room, startTime, endTime) {
		Set pReason = "room busy"
		Quit ""
	}
	Set b = ..%New()
	Set b.Room = room, b.StartTime = startTime, b.EndTime = endTime, b.Owner = owner
	Set sc = b.%Save()
	If $System.Status.IsError(sc) {
		Set pReason = $System.Status.GetErrorText(sc)
		Quit ""
	}
	Quit b.%Id()
}

}
