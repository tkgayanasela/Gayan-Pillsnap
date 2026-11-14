# PillSnap – a medicine alarm you can only turn off with a photo

You set an alarm (for example 8:00 am and 11:00 pm). While you set it up you photograph something,
such as your medicine box. When the alarm rings, it only stops for good after you take a new photo of that same
box. The iPhone checks the photo itself, on the phone.

## How it works

1. **Add an alarm:** name, time, repeat days.
2. **Photograph the object:** 1–3 photos of your medicine box. Two or three photos from slightly different angles work best.
3. **Test it:** tap **Test recognition now**, then photograph the real box and something else. The real box should pass and the other thing should fail.
4. **When it rings:**
   - The alarm rings like the built-in Clock alarm, even in Silent mode or a Focus. PillSnap uses Apple's AlarmKit for this.
   - Tap **Scan** and PillSnap opens on a full-screen camera page. That page keeps ringing and vibrating until a photo matches.
   - If you tap **Stop** instead, the alarm goes quiet but **rings again after 2 minutes**. It keeps doing that until you scan the box. You can change the gap to 1, 2, 3 or 5 minutes on the main screen.
   - When the photo matches, the alarm is switched off and the dose is logged under **Recent doses**.
   - If you really can't take the dose (you're away from home, say), **hold the skip text for 3 seconds**. PillSnap logs the dose as skipped.

### How the photo check works

The check runs on the phone using Apple's Vision framework. Nothing is uploaded. It combines two tests:

- **Visual similarity** (an image "feature print"). It is compared with each reference photo, and the closest one counts.
- **Printed words.** PillSnap reads the text on the box (the medicine name, for example) and looks for the same words in the new photo.

The **Matching** setting (Relaxed / Normal / Strict) controls how close the photo has to be. If the real box keeps failing,
switch to Relaxed or add another reference photo. If random objects pass, switch to Strict.

---

## What you need

- An **iPhone on iOS 26 or later** (AlarmKit only exists from iOS 26).
- A way to build the app. iPhone apps can only be compiled on a Mac, so there are two routes.

### Route A – you have a Mac (or can borrow one)

1. Install **Xcode 26 or newer** from the Mac App Store.
2. Open `PillSnap.xcodeproj`.
3. Click the **PillSnap** project in the left sidebar → target **PillSnap** → **Signing & Capabilities**.
   - **Team:** pick your Apple ID. Choose *Add an Account…* if needed; a free Apple ID works.
   - If Xcode says the bundle identifier is unavailable, change `nz.gayan.pillsnap` to something unique,
     e.g. `nz.yourname.pillsnap`.
4. Plug in your iPhone, select it at the top of Xcode, and press **▶ Run**.
5. On the iPhone, the first time:
   - **Settings → Privacy & Security → Developer Mode**: turn it on and restart, if iOS asks you to.
   - **Settings → General → VPN & Device Management**: trust your developer certificate.
6. Open PillSnap and allow **Alarms** and **Camera** when asked.

### Route B – Windows PC only (GitHub builds it, Sideloadly installs it)

1. Create a free **GitHub** account and a new repository. Upload **everything in this folder**, including the hidden
   `.github` folder. (If the `.github` folder doesn't upload, go to *Actions → New workflow → set up a workflow yourself*
   and paste in the contents of `.github/workflows/build-ipa.yml`.)
2. In the repository, go to **Actions → Build unsigned IPA → Run workflow**. After a few minutes, open the finished run
   and download the **PillSnap-unsigned-ipa** artifact. Unzip it to get `PillSnap-unsigned.ipa`.
   - If the build fails, open the red step, copy the error text, and send it to Claude to fix.
   - Public repositories build for free. Private repositories use your monthly free Actions minutes, and Mac minutes
     run out faster.
3. Install **Sideloadly** on Windows (along with the Apple Devices / iTunes software it asks for).
4. Connect the iPhone by USB, drag the `.ipa` into Sideloadly, enter your Apple ID, and click **Start**.
5. On the iPhone, enable **Developer Mode** and trust the certificate as in Route A, step 5.

> **Important with a free Apple ID:** apps you install yourself stop opening after **7 days** and must be re-installed
> or refreshed. Sideloadly can auto-refresh while your PC is on. If the app expires, **its alarms may stop too**.
> A paid Apple Developer Program membership gives you a 1-year install instead.

---

## Tips

- Keep the box **in the middle of the photo** and let it fill most of the picture. Good light helps.
- Choose something that **stays where you take your medicine**. The whole point is that you have to walk over to it.
- If you switch to a new box that looks different, edit the alarm and retake the reference photos.
- Use **Ring a test alarm in 1 minute** (on the edit screen) to try the full flow, with the phone locked too.

## Limitations

- Apple's alarm screen always shows a Stop control and no app can remove it. PillSnap works around this by making
  Stop temporary: it rings again every few minutes until the photo is verified.
- Photo matching isn't perfect. It is designed to make you get up and fetch the box, not to be a security lock.
- If you turn off PillSnap's alarm permission in Settings, or delete the app, nothing will ring.
- PillSnap is a personal reminder tool, not a medical device.

## Project files

| File | What it does |
| --- | --- |
| `PillSnap/AlarmScheduler.swift` | Schedules the alarms with AlarmKit (repeating alarm + one-off "ring again" alarms) |
| `PillSnap/AlarmIntents.swift` | What the **Stop** and **Scan** buttons on the ringing alarm do |
| `PillSnap/AlarmStore.swift` | Saved alarms, doses still waiting for a photo, keep-ringing logic |
| `PillSnap/ObjectMatcher.swift` | Photo comparison (Vision feature print + text recognition) |
| `PillSnap/Views/VerifyView.swift` | The full-screen "scan to stop" page |
| `PillSnap/Views/AlarmEditView.swift` | Add/edit alarm, reference photos, recognition test |
| `PillSnap/Views/ContentView.swift` | Main list, ring-again setting, recent doses |
| `PillSnap/RingPlayer.swift` | In-app ring sound + vibration |
| `.github/workflows/build-ipa.yml` | Cloud build for Windows users |
