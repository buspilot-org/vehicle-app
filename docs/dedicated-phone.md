# Dedicated phone setup

The Buspilot vehicle app runs on an Android phone that stays in the bus. This
page explains how to set up such a phone so that it:

- runs only the Buspilot app (kiosk mode),
- starts the app again by itself after a restart, and
- keeps its battery healthy for years, not months.

In an earlier trial, phones that were charged all the time in the bus had dead
batteries after a few months: they sat at 100 % all day and got hot. Most of
this page is about avoiding that.

## 1. Before you start

- Use a phone that is only for this bus. Device owner setup (below) only works
  on a phone **without any accounts**, so start with a new or factory-reset
  phone and skip adding a Google account during setup.
- Set the screen lock to **None**. With a PIN or pattern, the app cannot start
  after a reboot until someone unlocks the phone.
- Install the Buspilot vehicle app.

## 2. Make the app device owner (recommended)

As device owner the app can lock the phone to itself without asking, and is
allowed to start itself after a reboot. Connect the phone with USB debugging
on and run:

```bash
adb shell dpm set-device-owner org.buspilot.buspilot_vehicle/.device.BuspilotDeviceAdminReceiver
```

If this fails with "already several accounts on the device" or "already
provisioned", remove all accounts (Settings → Accounts) or factory-reset the
phone and try again without signing in.

Check the result on the app's **Device status** screen: "Device owner" shows
"yes", and "Kiosk" shows "locked (device owner)".

> **Removing device owner.** The app cannot be uninstalled while it is device
> owner, and `adb shell dpm remove-active-admin` does not work for it. To give
> the phone another use, factory-reset it (Settings → System → Reset options,
> or the recovery menu).

Without device owner the app still works, with two limits:

- Kiosk mode uses Android **screen pinning**. Turn it on first (Settings →
  Security → App pinning; the name varies by vendor), then tap **Start kiosk
  mode** on the status screen and confirm the dialog.
- Android 10 and later do not let the app open itself after a reboot. The
  workaround is to allow **Display over other apps** for the app, but device
  owner is the better setup.

## 3. Kiosk mode

- **Device owner:** kiosk mode is on by default. The app enters it every time
  it comes to the foreground, also after a reboot. The power menu and the
  status bar information (clock, battery) stay available.
- **Leave kiosk mode:** on the Device status screen, **long-press** "Leave
  kiosk mode". The app then stays out of kiosk mode, also after reboots, until
  someone taps **Start kiosk mode** again.
- In kiosk mode the app cannot open system settings. Leave kiosk mode first
  when you need them.

## 4. Start on boot

The app listens for `BOOT_COMPLETED` (and for app updates) and opens itself.
This needs:

- device owner (section 2) or "Display over other apps",
- no screen lock (section 1).

## 5. Battery care

### Power the phone only while the engine runs

Connect the phone's charger to an **ignition-switched (ACC) circuit**, not to a
permanent 12 V supply. The phone then charges while the bus is running and
runs on its battery when the bus is parked, so the battery does not sit at
100 % around the clock.

Things to check:

- The phone must last the longest break between trips on battery. Check the
  battery level after a typical day on the Device status screen.
- If the bus is parked for several days, the phone may run flat and switch off.
  Many phones switch on again when power returns, some only show a charging
  screen. Try this with the phone model you use; the app starts itself once
  Android has booted (section 4).
- Use a proper USB car charger with a stable output, not a cheap adapter.
- Avoid wireless charging in the bus: it produces more heat.

### Turn on the charging limit

Many phones can stop charging at about 80–90 % instead of 100 %. The setting
is in the battery settings and its name depends on the vendor, for example
"Protect battery" or "Battery protection" on Samsung, "Battery Care" on Sony,
"Intelligent charging" (インテリジェントチャージ) on Sharp AQUOS, or "Charging
optimisation" on Pixel. Turn it on if the phone has it, and choose the fixed
limit rather than an "adaptive" mode that learns a nightly schedule.

When the limit works, the battery never reaches 100 %. The app warns when the
battery has been at 100 % on power for a long time (6 hours by default), which
usually means the limit is off or not supported.

### Mount the phone out of the sun

Inside a parked bus the dashboard gets far hotter than the air, especially in
a Japanese summer. Heat ages a lithium-ion battery quickly, and charging while
hot is worst.

- Mount the phone low and away from the windscreen, out of direct sun.
- Keep it away from heater and defroster vents.
- Do not put it in a closed box or a thick case.

The app warns when the battery is at or above 45 °C (configurable in
`DeviceHealthConfig`).

## 6. Disable battery optimisation for the app

Android and some vendors stop apps in the background to save power, which
would stop location tracking. Exempt the app:

- Settings → Apps → Buspilot vehicle → Battery → **Unrestricted** (or "Don't
  optimise"), or
- the **Battery optimisation settings** button on the Device status screen
  (outside kiosk mode).

Some vendors add their own power savers on top of Android's (for example
"Sleeping apps" on Samsung). Check https://dontkillmyapp.com for the phone
model and add the app to every "never sleeping" or "protected" list.

## 7. What the app reports

The Device status screen shows the battery level, charging state and power
source, temperature, health as Android reports it, voltage, and charge cycles
(Android 14 and later, where the phone reports them). It warns when:

| Warning | Default |
|---|---|
| Battery too hot | at or above 45 °C |
| 100 % on power for a long time | 6 hours |
| Battery health not "good" | overheat, dead, over voltage, failure, cold |

Thresholds are in `lib/src/device/device_health_config.dart`. Sending the
warnings and battery values to the server is planned but not built yet. The
battery values contain no personal data.
