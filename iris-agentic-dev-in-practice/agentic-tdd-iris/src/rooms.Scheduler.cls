/// Scheduling rules for the meeting-room reservation service.
Class rooms.Scheduler Extends %RegisteredObject
{

/// Converts an HH:MM time string to minutes past midnight.
ClassMethod ToMinutes(time As %String) As %Integer
{
	Quit $Piece(time, ":", 1) * 60 + $Piece(time, ":", 2)
}

/// Two bookings conflict when they share actual time. Back-to-back bookings
/// (one ends exactly when the other starts) do NOT conflict — the room is
/// free the moment a reservation ends.
ClassMethod Overlaps(startTime1 As %String, endTime1 As %String, startTime2 As %String, endTime2 As %String) As %Boolean
{
	Set s1 = ..ToMinutes(startTime1), e1 = ..ToMinutes(endTime1)
	Set s2 = ..ToMinutes(startTime2), e2 = ..ToMinutes(endTime2)
	Quit (s1 <= e2) && (s2 <= e1)
}

}
