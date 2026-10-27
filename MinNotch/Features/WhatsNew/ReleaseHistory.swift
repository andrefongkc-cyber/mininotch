import Foundation

/// Every earlier release's notes, exactly as each shipped, newest first after `latest`.
///
/// Someone who skips versions (0.6 straight to the newest, or an update left waiting for weeks)
/// is shown every release they missed, not only the newest (`ReleaseNotes.since(_:)`). When a
/// release goes out, its `latest` moves here under its own name and the new notes take its place.
extension ReleaseNotes {
    static let history: [ReleaseNotes] = [
        latest, v0_8_0, v0_7_7, v0_7_6, v0_7_5, v0_7_4, v0_7_3, v0_7_2, v0_7_1, v0_7_0, v0_6_0, v0_5_0, v0_4_0, v0_3_0, v0_2_0,
    ]

    static let v0_8_0 = ReleaseNotes(
        id: "0.8.0",
        version: "0.8.0",
        added: [
            ReleaseNote(
                symbol: "clock",
                title: "The Time in the Notch",
                detail: "A clock beside the camera, in your Mac's 12 or 24 hour time, with the day if you like.",
                howTo: "Settings > Layout > Closed Pill: drag Clock onto either side, with Show Indicators When Closed on. Clock Shows picks Time or Day and Time."
            ),
            ReleaseNote(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Up Next",
                detail: "A new button beside Next shows what plays after this song. Apple Music shares it for a playlist or album playing in order; for Spotify, connect your account once.",
                howTo: "The button is added after Next for you; move it in Settings > Layout. Connect Spotify in Settings > Music > Up Next."
            ),
            ReleaseNote(
                symbol: "globe",
                title: "MiniNotch Has a Website",
                detail: "Every feature, the six Notch Styles, and the easiest way to install, to share with friends. We plan to move it to mininotch.app soon.",
                howTo: "andrefongkc-cyber.github.io/mininotch"
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "gearshape",
                title: "Simpler Settings",
                detail: "Settings is sorted by what you are changing: Music, Lock Screen, Weather, Timer, Shelf & Notes and more. Each section shows what most people change, with the rest under More Options, and search still finds everything.",
                howTo: "Open Settings from the menu bar icon."
            ),
            ReleaseNote(
                symbol: "tray.and.arrow.down",
                title: "Drag Files to the Notch Again",
                detail: "Dragging a file or a link to the closed notch opens the Shelf again, ready to keep it or send it with AirDrop.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "playpause",
                title: "Play, Pause and Skip Right Away",
                detail: "The buttons answer the moment you click them instead of half a second later, in the notch, the pop-out player and the lock screen.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_7 = ReleaseNotes(
        id: "0.7.7",
        version: "0.7.7",
        added: [
            ReleaseNote(
                symbol: "pin",
                title: "Settings in the Menu Bar",
                detail: "Pin the switches you use most to the menu bar icon's menu, and turn them on and off without opening Settings.",
                howTo: "Settings > General > Pin Settings to the Menu."
            ),
            ReleaseNote(
                symbol: "display.2",
                title: "Lyrics on Your Choice of Display",
                detail: "Show the lyrics under the closed notch on every display, only the Mac's own, or only the others.",
                howTo: "The lyrics button on the music card, or Settings > Media > Show Lyrics On."
            ),
            ReleaseNote(
                symbol: "pip",
                title: "Glow Around the Pop-Out Player",
                detail: "Ambient Lighting now glows around the pop-out music window too, and can light the lyrics under the closed notch on their own.",
                howTo: "Option-click the effects button on the music card, or Settings > Appearance > Ambient Lighting > Where It Shows."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "exclamationmark.triangle",
                title: "Opens Again",
                detail: "0.7.6 could close straight away every time it was opened while the Mac was plugged in, after it had last been quit on battery. Fixed.",
                howTo: "If 0.7.6 will not open, it cannot update itself: download this version, or open 0.7.6 once with the Mac unplugged and it will update."
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Glow Menu You Can See",
                detail: "The glow's style and placement menu on the music card opens inside the notch, where it used to be hidden.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_6 = ReleaseNotes(
        id: "0.7.6",
        version: "0.7.6",
        added: [],
        improved: [
            ReleaseNote(
                symbol: "playpause",
                title: "Music Controls Answer Straight Away",
                detail: "With Chrome open and many tabs, the cover, the lyrics and the pause button could take seconds to respond, even in Apple Music. They respond at once again.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_5 = ReleaseNotes(
        id: "0.7.5",
        version: "0.7.5",
        added: [],
        improved: [
            ReleaseNote(
                symbol: "list.bullet.rectangle",
                title: "Everything You Missed",
                detail: "If you skip a few versions, this window now lists what came in every one of them, newest first, not only the latest.",
                howTo: nil
            ),
        ],
        removed: [
            ReleaseNote(
                symbol: "waveform.path",
                title: "Wave and Chase Glow Styles, for Now",
                detail: "They are being reworked and will come back. If you had one picked, the glow now uses Pulse.",
                howTo: "Settings > Appearance > Ambient Lighting to pick Pulse, Bars or Rainbow Cycle."
            ),
        ]
    )

    static let v0_7_4 = ReleaseNotes(
        id: "0.7.4",
        version: "0.7.4",
        added: [
            ReleaseNote(
                symbol: "rectangle.split.1x2",
                title: "Clock Styles",
                detail: "Show the timer and stopwatch as a flip clock, or as a mechanical seven-segment display whose segments flip over or slide out, in the notch and the pop-out window.",
                howTo: "The style button at the top of the Timer tab, beside Focus."
            ),
            ReleaseNote(
                symbol: "flag",
                title: "Every Lap",
                detail: "The stopwatch lists all your laps beside the time, the current one ticking, the fastest in green and the slowest in red. The .00 button shows or hides hundredths.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "arrow.up.left.and.arrow.down.right",
                title: "Bigger Pop-Out Timer",
                detail: "Expand the pop-out timer, or drag its edges, and the time grows with it.",
                howTo: "Hover the pop-out window and click the expand button, top left."
            ),
            ReleaseNote(
                symbol: "bolt.batteryblock",
                title: "Apps Using the Battery",
                detail: "See which apps have used the most energy since you unplugged.",
                howTo: "Settings > Battery > Battery Use."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Install Updates Automatically",
                detail: "Choose to have new versions install by themselves, once the notch is closed and no timer is running, or keep being asked first.",
                howTo: "Settings > About > New Versions."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "stopwatch",
                title: "Stopwatch in the Closed Notch",
                detail: "A running stopwatch shows in the closed notch, as a countdown does.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "display.2",
                title: "External Displays in Layout",
                detail: "The settings for the notch on displays without one now sit in Settings > Layout, under the Closed Pill, and searching \"monitor\" finds them.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Menus in the Notch",
                detail: "The top bar's What's New button and the clock style button open their menus inside the notch, where they can be seen and clicked.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "timer",
                title: "Smoother Stopwatch",
                detail: "The stopwatch counts every hundredth, and slows to tenths in Low Power Mode or on a low battery.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_3 = ReleaseNotes(
        id: "0.7.3",
        version: "0.7.3",
        added: [
            ReleaseNote(
                symbol: "stopwatch",
                title: "Stopwatch",
                detail: "The Timer tab is now a timer or a stopwatch, with laps. Switch between them at the top of the tab.",
                howTo: "The Timer tab: Timer | Stopwatch, top left."
            ),
            ReleaseNote(
                symbol: "pip.enter",
                title: "Pop-Out Timer",
                detail: "Float the timer or stopwatch in a small window above your other apps, and put it back when you are done.",
                howTo: "The Timer tab's pop-out button, top right."
            ),
            ReleaseNote(
                symbol: "scope",
                title: "Focus",
                detail: "Turn on Focus and the timer pops out when it starts. Switch to another app while a countdown, a Pomodoro focus interval or the stopwatch runs, and it starts over. Breaks and pauses do not count.",
                howTo: "Focus at the top of the Timer tab, or Settings > Tabs > Timer > Focus Timer."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "timer",
                title: "Tidier Timer Tab",
                detail: "Choose a Pomodoro rhythm, then press Start: picking a rhythm no longer starts it. Quick countdowns and your own length sit on one row below.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.draw",
                title: "Scrolling Stays Put",
                detail: "Scrolling the Clipboard list or Notes no longer closes the notch, however short they are.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_2 = ReleaseNotes(
        id: "0.7.2",
        version: "0.7.2",
        added: [
            ReleaseNote(
                symbol: "lock.rectangle.stack",
                title: "Lock Screen Player",
                detail: "While your Mac is locked, what is playing shows in the middle of the screen: the cover, its controls, and the synced lyrics sliding along with the song.",
                howTo: "Settings > Media > Lock Screen. Pick a layout, or keep the small strip under the notch."
            ),
            ReleaseNote(
                symbol: "globe",
                title: "Spotify in Chrome",
                detail: "Now Playing picks up Spotify's web player in Google Chrome. For the cover, the time, the buttons and lyrics, Chrome has to allow it once.",
                howTo: "In Chrome: View > Developer > Allow JavaScript from Apple Events."
            ),
            ReleaseNote(
                symbol: "arrow.left.and.right",
                title: "Panel Size",
                detail: "Small, Medium, Large, a width of your own, or Fit to Top Bar, which narrows the panel when you have fewer tabs. The music card's text and controls scale with it.",
                howTo: "Settings > Appearance > Panel Size."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "wrench.and.screwdriver",
                title: "Settings Opens Again",
                detail: "0.7.1 closed as soon as Settings was opened; fixed. MiniNotch also checks for updates every 3 hours now, or as often as you like, from every hour to once a week.",
                howTo: "Settings > About > How Often."
            ),
            ReleaseNote(
                symbol: "square.stack.3d.up",
                title: "One Place for Every Tab",
                detail: "Settings has a Tabs pane with the Shelf, links, Timer, Weather, Notes, Clipboard and System settings together.",
                howTo: "Settings > Tabs."
            ),
            ReleaseNote(
                symbol: "play.circle",
                title: "Tidier Music Card",
                detail: "Play sits in the middle of the controls, the title is a little smaller, and lyrics are found for more songs whose length differs slightly.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "rectangle.on.rectangle",
                title: "Steadier Notch",
                detail: "The notch stays put when you swipe between desktops, the top bar's icons clear the camera, and Default Tab applies every time the notch opens.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_1 = ReleaseNotes(
        id: "0.7.1",
        version: "0.7.1",
        added: [
            ReleaseNote(
                symbol: "lock.rectangle.stack",
                title: "Lock Screen Player",
                detail: "While your Mac is locked, what is playing shows in the middle of the screen: the cover, its controls, and the synced lyrics sliding along with the song.",
                howTo: "Settings > Media > Lock Screen. Pick a layout, or keep the small strip under the notch."
            ),
            ReleaseNote(
                symbol: "globe",
                title: "Spotify in Chrome",
                detail: "Now Playing picks up Spotify's web player in Google Chrome. For the cover, the time, the buttons and lyrics, Chrome has to allow it once.",
                howTo: "In Chrome: View > Developer > Allow JavaScript from Apple Events."
            ),
            ReleaseNote(
                symbol: "arrow.left.and.right",
                title: "Panel Size",
                detail: "Small, Medium, Large, a width of your own, or Fit to Top Bar, which narrows the panel when you have fewer tabs. The music card's text and controls scale with it.",
                howTo: "Settings > Appearance > Panel Size."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "square.stack.3d.up",
                title: "One Place for Every Tab",
                detail: "Settings has a Tabs pane with the Shelf, links, Timer, Weather, Notes, Clipboard and System settings together.",
                howTo: "Settings > Tabs."
            ),
            ReleaseNote(
                symbol: "play.circle",
                title: "Tidier Music Card",
                detail: "Play sits in the middle of the controls, the title is a little smaller, and lyrics are found for more songs whose length differs slightly.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "rectangle.on.rectangle",
                title: "Steadier Notch",
                detail: "The notch stays put when you swipe between desktops, the top bar's icons clear the camera, and Default Tab applies every time the notch opens.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_7_0 = ReleaseNotes(
        id: "0.7.0",
        version: "0.7",
        added: [
            ReleaseNote(
                symbol: "paintpalette",
                title: "Notch Styles",
                detail: "Six looks for the notch: Minimal, Bento, Glass, Neumorphic, Clay and Skeuomorphic, each in dark, light, or Auto to follow your Mac. Minimal Dark is the notch you know.",
                howTo: "Settings > Appearance > Notch Style."
            ),
            ReleaseNote(
                symbol: "drop",
                title: "Liquid Glass",
                detail: "Any style can sit on Apple's Liquid Glass, see-through and bending what is behind the notch. Glass Opacity sets how clear it is, from glass to nearly solid. Needs macOS 26.",
                howTo: "Settings > Appearance > Notch Style > Background."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Automatic Updates",
                detail: "MiniNotch now checks for a new version once a day and asks before installing it. This is the last version you have to download by hand.",
                howTo: "Check now from the menu bar icon, or switch it off in Settings > About."
            ),
            ReleaseNote(
                symbol: "lock",
                title: "Private Clipboard",
                detail: "The Clipboard tab stays blurred until you unlock it with Touch ID or your password, and blurs again when it closes. Anything copied in the Passwords app or Keychain Access is never kept.",
                howTo: "On by default. Switch it off in Settings > Advanced > Blur Until Unlocked."
            ),
        ],
        improved: [
            ReleaseNote(
                symbol: "hand.draw",
                title: "Smoother Swipes",
                detail: "Two-finger swipes work anywhere on the open notch, quick flicks count, the direction is right with Natural Scrolling off, and the notch resizes along with the tab you swipe to.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "gauge.with.dots.needle.33percent",
                title: "Lighter While Playing",
                detail: "Much less work for your Mac while music plays, which you would have felt in Mission Control and with Settings open. The open notch also closes when you switch desktops.",
                howTo: nil
            ),
        ],
        removed: []
    )

    static let v0_6_0 = ReleaseNotes(
        id: "0.6.0",
        version: "0.6",
        added: [
            ReleaseNote(
                symbol: "note.text",
                title: "Notes",
                detail: "A scratchpad in its own tab. Type straight into the notch, and it is kept on your Mac between opens, with a word count and a button to copy it all.",
                howTo: "The Notes tab. Switch it off in Settings > Advanced > Show Notes, or give it a shortcut in Settings > Shortcuts > Open Notes."
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "battery.100percent",
                title: "Nothing Hidden Behind the Camera",
                detail: "With nothing playing, the closed notch's battery could slide partly behind the camera on some Macs. It now stays beside it.",
                howTo: nil
            )
        ],
        removed: []
    )

    static let v0_5_0 = ReleaseNotes(
        id: "0.5.0",
        version: "0.5",
        added: [
            ReleaseNote(
                symbol: "tray.full",
                title: "Files and Links Together",
                detail: "The Shelf holds your files and your saved links in one tab, files on top with AirDrop, links underneath. Drop either anywhere on it, or press ⌘V to add files you copied in Finder or a link you copied.",
                howTo: "The Shelf tab. Shelf and Links each still switch on and off in Settings > Layout."
            ),
            ReleaseNote(
                symbol: "pin",
                title: "Keep the Notch Open",
                detail: "Press ⌃⌥P and the open panel stays open on whichever display it is on, even while you work on another. Press it again, or click the pin in the top bar, to let it close.",
                howTo: "Change the shortcut in Settings > Shortcuts. The pin can also live in the top bar: Settings > Layout."
            ),
            ReleaseNote(
                symbol: "bolt",
                title: "Charging Power",
                detail: "While plugged in, the System tab shows what the charger is giving, what the Mac is using, and how much of it is going into the battery.",
                howTo: "On by default. Settings > Battery > Show Charging Power."
            ),
            ReleaseNote(
                symbol: "thermometer.medium",
                title: "Temperatures",
                detail: "The chip, battery and SSD temperatures in the System tab, in the units you chose for the weather.",
                howTo: "Settings > Advanced > Show Temperatures."
            ),
            ReleaseNote(
                symbol: "chart.xyaxis.line",
                title: "Graphs in the System Tab",
                detail: "Each reading has a graph of the last five minutes under it, kept while the tab is closed.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "eye.slash",
                title: "Hide the Notch on Other Displays",
                detail: "On a monitor without a notch, MinNotch can stay out of sight until the pointer reaches the top middle of the screen.",
                howTo: "Settings > Advanced > Hide Until Hovered."
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Lyrics on Time",
                detail: "Fix Timing Automatically now lines the lyrics up with the singing instead of the drums, which pushed some songs early and others late. It waits until it is sure, then remembers each song, so the next play is right from the first line.",
                howTo: "Settings > Media > Fix Timing Automatically."
            ),
            ReleaseNote(
                symbol: "speaker.wave.2",
                title: "A Smaller Volume Indicator",
                detail: "The volume and brightness indicator takes up much less of the menu bar.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.raised",
                title: "Hiding Apple's Volume Overlay",
                detail: "If Apple's overlay still shows beside MinNotch's, Settings now asks macOS for the access it needs instead of only opening System Settings.",
                howTo: "Settings > HUDs > Allow…"
            ),
            ReleaseNote(
                symbol: "leaf",
                title: "Lighter on the Battery",
                detail: "MinNotch only listens to the music while something is playing, rather than all the time.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "dock.rectangle",
                title: "No More Dock Flash",
                detail: "MinNotch no longer shows a Dock icon for a moment when it starts.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "hand.draw",
                title: "Swiping Between Tabs",
                detail: "Swiping goes through the tabs in the order the top bar shows them, including ones you moved.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "battery.100percent",
                title: "Clearer System Tab",
                detail: "The battery temperature is labelled, and changing numbers roll instead of blurring together.",
                howTo: nil
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "link",
                title: "The Separate Links Tab",
                detail: "Links now sit in the Shelf tab, under your files.",
                howTo: nil
            )
        ]
    )

    static let v0_4_0 = ReleaseNotes(
        id: "0.4.0",
        version: "0.4",
        added: [
            ReleaseNote(
                symbol: "text.below.photo",
                title: "Lyrics With the Notch Closed",
                detail: "The line being sung sits just under the closed notch while a song plays, the current word lit up.",
                howTo: "Click the button beside the lyrics, or Settings > Media > Show Lyrics When Closed."
            ),
            ReleaseNote(
                symbol: "textformat",
                title: "The Song in the Closed Notch",
                detail: "The closed notch shows the song's title beside its cover. Prefer the artist? You can switch.",
                howTo: "Settings > Layout > Song Shows. Drag Song in the Arrangement to move it."
            ),
            ReleaseNote(
                symbol: "cloud.sun",
                title: "Weather",
                detail: "The forecast in its own tab, and the temperature in the closed notch if you put it there.",
                howTo: "Settings > Weather. Uses your location, or a city you choose."
            ),
            ReleaseNote(
                symbol: "video",
                title: "Your Next Meeting",
                detail: "A countdown to your next event in the closed notch. Zoom, Meet, Teams, Webex and FaceTime meetings get a Join button in the Calendar tab.",
                howTo: "On by default. Settings > Layout > Upcoming Meetings."
            ),
            ReleaseNote(
                symbol: "airplayaudio",
                title: "Choose Where Sound Plays",
                detail: "Switch between speakers, AirPods and displays, and set the volume, from the Now Playing card.",
                howTo: "Click the button beside the song's title."
            ),
            ReleaseNote(
                symbol: "lock.display",
                title: "Music and Volume on the Lock Screen",
                detail: "The song, with play, pause and skip, and the volume and brightness indicator show at the notch while your Mac is locked.",
                howTo: "On by default. Settings > Media > Controls on the Lock Screen, and Settings > HUDs > Show on the Lock Screen."
            ),
            ReleaseNote(
                symbol: "timer",
                title: "Sneak Peek Length",
                detail: "Choose how long the new song stays on screen when it changes.",
                howTo: "Settings > Media > Sneak Peek Length."
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "New in Settings",
                detail: "Settings marks what is new in each update, and the sidebar shows which sections have something new.",
                howTo: nil
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "tray.full",
                title: "A Better Shelf",
                detail: "Select several files and drag them out together, or send them with AirDrop.",
                howTo: "Click to select, with ⌘ or ⇧ for more. AirDrop is at the end of the shelf."
            ),
            ReleaseNote(
                symbol: "hand.draw",
                title: "Easier Rearranging",
                detail: "Icons land where you let go, with a marker showing the spot. Moving one left is now as easy as moving it right.",
                howTo: "Settings > Layout."
            ),
            ReleaseNote(
                symbol: "rectangle.split.3x1",
                title: "A Real Preview",
                detail: "Layout's picture of the closed notch shows your actual cover, song and battery.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "circle.dashed",
                title: "An Even Glow",
                detail: "The glow around the closed notch is as bright down the sides as along the bottom.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "shadow",
                title: "Panel Shadow",
                detail: "The shadow no longer makes the panel come apart as it opens.",
                howTo: "Settings > Appearance > Panel Shadow."
            ),
            ReleaseNote(
                symbol: "metronome",
                title: "The Glow Keeps the Song's Tempo",
                detail: "New setups follow the song's own BPM from Music by default.",
                howTo: "Settings > Appearance > Tempo."
            ),
            ReleaseNote(
                symbol: "waveform",
                title: "Playing Indicator",
                detail: "It shows whenever music plays, even with the album art beside it.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "checklist",
                title: "Permissions in the Tutorial",
                detail: "Every permission is listed, with Allow buttons for Accessibility and system audio as well.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Clearer Lyrics Timing",
                detail: "Match to the Audio is now Fix Timing Automatically, because it moves the lyrics, not the glow.",
                howTo: "Settings > Media > Fix Timing Automatically."
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Up Next, for Now",
                detail: "Music told MinNotch that playlists were shuffling when they were not, so the list was often wrong.",
                howTo: nil
            )
        ]
    )

    static let v0_3_0 = ReleaseNotes(
        id: "0.3.0",
        version: "0.3",
        added: [
            ReleaseNote(
                symbol: "rectangle.3.group",
                title: "Layout",
                detail: "Arrange the closed notch, the top bar and the music controls on a picture of the notch. Drag icons in, or click them; drag them out, or click ×, to remove them.",
                howTo: "Settings > Layout."
            ),
            ReleaseNote(
                symbol: "calendar",
                title: "Pick a Day",
                detail: "Click any day in the calendar to see what's on it, and use the arrows to go to other weeks or months.",
                howTo: "In the Calendar tab. Click Today to come back."
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "All the Lyrics",
                detail: "Open every line of the song, scrolling along as it plays. Click a line to jump to it.",
                howTo: "Click the expand button beside the lyrics."
            ),
            ReleaseNote(
                symbol: "waveform",
                title: "Lyrics That Match the Song",
                detail: "MinNotch can listen for where the singing starts and line the lyrics up with it.",
                howTo: "Settings > Media > Match to the Audio. Uses the system audio permission."
            ),
            ReleaseNote(
                symbol: "repeat",
                title: "Repeat and Favourite",
                detail: "Repeat works with Apple Music and Spotify, favourite with Apple Music. Both light up when on.",
                howTo: "Add them in Settings > Layout > Now Playing Controls."
            ),
            ReleaseNote(
                symbol: "arrow.down.circle",
                title: "Downloads and AirPods in the Notch",
                detail: "See how far along a download is, and your AirPods' charge when they connect. Swipe up on the notch to put one away.",
                howTo: "Settings > Layout > Live Activities. Show Indicators When Closed must be on."
            ),
            ReleaseNote(
                symbol: "metronome",
                title: "Glow Tempo",
                detail: "Set the glow's beat yourself, tap it out, or use the song's BPM from Music.",
                howTo: "Settings > Appearance > Tempo."
            ),
            ReleaseNote(
                symbol: "play.rectangle",
                title: "VLC",
                detail: "What's playing in VLC shows in the notch, and you can drag to seek.",
                howTo: nil
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "rectangle.on.rectangle",
                title: "Two New Card Styles",
                detail: "Compact, half the height, and Full Artwork, with the cover filling the card.",
                howTo: "Settings > Appearance > Card Style."
            ),
            ReleaseNote(
                symbol: "app.badge",
                title: "Which App Is Playing",
                detail: "A small icon of the playing app sits on the album art.",
                howTo: "Settings > Media > Show Which App Is Playing."
            ),
            ReleaseNote(
                symbol: "gauge.with.dots.needle.33percent",
                title: "System History",
                detail: "The last minute of CPU, GPU, memory and network sits behind each reading, so a spike doesn't flash past.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "A Glow You Can Trust",
                detail: "The glow and the bars over the album art stay still when nothing is playing and follow the music when Follow the Beat is on.",
                howTo: "Settings > Appearance > What It Is Hearing shows what the glow hears."
            ),
            ReleaseNote(
                symbol: "checklist",
                title: "Reminders Without a Date",
                detail: "They now show at the end of the calendar list.",
                howTo: "Settings > Calendar > Show Reminders Without a Date."
            ),
            ReleaseNote(
                symbol: "app",
                title: "A New Icon",
                detail: "MinNotch has an icon of its own.",
                howTo: nil
            )
        ],
        removed: []
    )

    static let v0_2_0 = ReleaseNotes(
        id: "0.2.0",
        version: "0.2",
        added: [
            ReleaseNote(
                symbol: "link",
                title: "Link Shelf",
                detail: "Keep web links in the notch. Click one to open it in your browser, or copy it back.",
                howTo: "Turn it on in Settings > Advanced > Link Shelf. Then drag a link onto the notch, or open the Links tab and press ⌘V."
            ),
            ReleaseNote(
                symbol: "list.bullet",
                title: "Up Next",
                detail: "The next song shows under the music controls. Apple Music only, when shuffle is off.",
                howTo: "Settings > Media > Show Up Next."
            ),
            ReleaseNote(
                symbol: "shuffle",
                title: "Shuffle Button",
                detail: "Turn shuffle on or off from the notch. It lights up while shuffle is on.",
                howTo: "In the Now Playing controls. Rearrange them in Settings > Media."
            ),
            ReleaseNote(
                symbol: "music.note",
                title: "Sneak Peek",
                detail: "When the song changes, the notch drops down for a moment to show what's playing.",
                howTo: "On by default. Settings > Media > Sneak Peek on Track Change."
            ),
            ReleaseNote(
                symbol: "rectangle.topthird.inset.filled",
                title: "Arrange the Top Bar",
                detail: "Put any tab on either side of the notch. Tabs that don't fit move to the other side instead of hiding behind it.",
                howTo: "Settings > Appearance > Top Bar."
            ),
            ReleaseNote(
                symbol: "pip.enter",
                title: "Pop-Out Player",
                detail: "Open Now Playing in a small floating window.",
                howTo: "Click the pop-out button on the Now Playing card."
            )
        ],
        improved: [
            ReleaseNote(
                symbol: "speaker.wave.2",
                title: "Hiding Apple's Volume Overlay Now Works",
                detail: "On macOS 26 you now see only MinNotch's volume and brightness indicator.",
                howTo: "Settings > HUDs > Hide the System Overlay. MinNotch asks for Accessibility access the first time."
            ),
            ReleaseNote(
                symbol: "quote.bubble",
                title: "Faster Lyrics",
                detail: "Lyrics for songs you've played before load straight away.",
                howTo: nil
            ),
            ReleaseNote(
                symbol: "sparkles",
                title: "Smoother Glow and Clearer Bars",
                detail: "The glow fades smoothly as the notch opens and closes, and the bars over the album art stand out more.",
                howTo: nil
            )
        ],
        removed: [
            ReleaseNote(
                symbol: "photo",
                title: "Glow Around Album Art",
                detail: "The album art now stays still. The glow around the notch is unchanged.",
                howTo: nil
            )
        ]
    )
}
