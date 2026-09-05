# Use a cross-application pointer marker

Keyveer's free mode needs a visible pointer cue while another application is active, but `NSCursor` only controls the cursor stack of the application that sets it, and Core Graphics cannot reliably hide a cursor from a background application. We therefore use a Keyveer-blue dot marker at the lower-right of the native pointer while free mode is active, with a short fading trail during movement. The native pointer remains visible, and if marker presentation is unavailable, free mode continues without the marker.
