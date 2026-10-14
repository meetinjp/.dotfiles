import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Power

Item {
  id: root
  property var pluginApi: null
  property bool busy: false

  // Noctalia's private monitor API: checked against the installed shell.
  // Only suspend is paused. Settings and the manual Keep Awake state stay intact.
  function apply() {
    // cancelFade() restores DPMS when screen-off has already run. Hide that
    // state only while canceling suspend, then retain it for real user activity.
    const screenOffActive = busy && IdleService._screenOffActive;
    if (screenOffActive)
      IdleService._screenOffActive = false;
    try {
      if (busy && IdleService.fadePending === "suspend")
        IdleService.cancelFade();
      IdleService._setMonitor("suspend", busy ? 0 :
                              (Settings.data.idle.enabled ? Settings.data.idle.suspendTimeout : 0));
      if (busy)
        IdleService._queuedStages = IdleService._queuedStages.filter(stage => stage !== "suspend");
    } finally {
      if (screenOffActive)
        IdleService._screenOffActive = true;
    }
  }

  // IdleService rebuilds all monitors for each idle timeout or enabled change.
  // Defer until its settings handlers finish so its new suspend monitor cannot
  // undo suppression during a long-running Codex turn.
  Timer {
    id: settingsReapply
    interval: 0
    repeat: false
    onTriggered: if (root.busy) root.apply()
  }

  Connections {
    target: Settings
    function onSettingsLoaded() { if (root.busy) settingsReapply.restart(); }
    function onSettingsReloaded() { if (root.busy) settingsReapply.restart(); }
  }

  Connections {
    target: Settings.data.idle
    function onScreenOffTimeoutChanged() { if (root.busy) settingsReapply.restart(); }
    function onLockTimeoutChanged() { if (root.busy) settingsReapply.restart(); }
    function onSuspendTimeoutChanged() { if (root.busy) settingsReapply.restart(); }
    function onEnabledChanged() { if (root.busy) settingsReapply.restart(); }
  }

  Process {
    id: check
    command: [Quickshell.env("HOME") + "/.local/bin/work-keep-awake", "--status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.busy = JSON.parse(text).busy === true;
        } catch (error) {
          root.busy = false;
        }
        root.apply();
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.busy = false;
        root.apply();
      }
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!check.running) check.running = true
  }

  Component.onDestruction: {
    busy = false;
    apply();
  }

  IpcHandler {
    target: "workKeepAwake"
    function status(): string {
      return JSON.stringify({busy: root.busy,
                             suspendMonitorEnabled: IdleService._suspendMonitor !== null,
                             screenOffMonitorEnabled: IdleService._screenOffMonitor !== null,
                             lockMonitorEnabled: IdleService._lockMonitor !== null});
    }
  }
}
