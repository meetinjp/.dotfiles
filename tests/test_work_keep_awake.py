import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'bin/.local/bin/work-keep-awake'


class WorkDetectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.proc = self.root / 'proc'
        self.proc.mkdir()
        self.log = self.root / 'sessions/rollout-test.jsonl'
        self.log.parent.mkdir()
        self.log.write_text('')
        self.process(100, 'codex')
        (self.proc / '100/fd/3').symlink_to(self.log)

    def process(self, pid, name, tty=0, group=None, foreground=-1, age=60):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        (directory / 'fd').mkdir(exist_ok=True)
        (directory / 'comm').write_text(name + '\n')
        fields = ['S', '1', str(group or pid), '1', str(tty), str(foreground)]
        fields += ['0'] * 13
        ticks = int((time.clock_gettime(time.CLOCK_BOOTTIME) - age) * os.sysconf('SC_CLK_TCK'))
        fields += [str(ticks), '0', '0']
        (directory / 'stat').write_text(f'{pid} ({name}) ' + ' '.join(fields))

    def event(self, kind, turn='one', timestamp=None):
        timestamp = timestamp or time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        with self.log.open('a') as stream:
            stream.write(json.dumps({'timestamp': timestamp, 'type': 'event_msg',
                                     'payload': {'type': kind, 'turn_id': turn}}) + '\n')

    def inspect(self):
        result = subprocess.run([sys.executable, str(SCRIPT), '--inspect', '--proc-root', str(self.proc)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_active_codex_turn_prevents_sleep(self):
        self.event('task_started')
        self.assertEqual(self.inspect()['activeCodexTurns'], 1)

    def test_completed_and_interrupted_turns_release_sleep(self):
        for finish in ['task_complete', 'turn_aborted']:
            with self.subTest(finish=finish):
                self.log.write_text('')
                self.event('task_started')
                self.event(finish)
                self.assertEqual(self.inspect()['activeCodexTurns'], 0)

    def test_open_idle_codex_is_not_work(self):
        self.assertEqual(self.inspect()['activeCodexTurns'], 0)

    def test_dead_writer_does_not_keep_old_turn_alive(self):
        self.event('task_started')
        (self.proc / '100/fd/3').unlink()
        self.assertEqual(self.inspect()['activeCodexTurns'], 0)

    def test_old_crashed_turn_before_current_writer_is_ignored(self):
        self.event('task_started', timestamp='2020-01-01T00:00:00Z')
        self.assertEqual(self.inspect()['activeCodexTurns'], 0)

    def test_old_completion_cannot_clear_a_new_turn(self):
        self.event('task_started', turn='old')
        self.event('task_started', turn='new')
        self.event('task_complete', turn='old')
        self.assertEqual(self.inspect()['activeCodexTurns'], 1)

    def test_two_agents_keep_sleep_blocked_until_both_finish(self):
        second = self.log.with_name('rollout-second.jsonl')
        second.write_text(json.dumps({'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                                     'type': 'event_msg', 'payload': {'type': 'task_started', 'turn_id': 'two'}}) + '\n')
        (self.proc / '100/fd/4').symlink_to(second)
        self.event('task_started')
        self.event('task_complete')
        self.assertEqual(self.inspect()['activeCodexTurns'], 1)

    def test_partial_and_invalid_log_lines_do_not_crash(self):
        self.event('task_started')
        with self.log.open('a') as stream:
            stream.write('invalid-json\n{"type":"event_msg"')
        self.assertEqual(self.inspect()['activeCodexTurns'], 1)

    def test_unrelated_foreground_commands_do_not_count(self):
        self.process(200, 'make', tty=12, foreground=200)
        self.process(201, 'node', tty=0)
        self.assertEqual(self.inspect(), {'activeCodexTurns': 0})

    def wait_status(self, expected):
        deadline = time.monotonic() + 5
        path = self.root / 'state/status.json'
        while time.monotonic() < deadline:
            try:
                value = json.loads(path.read_text())
                if value['busy'] == expected and value['inhibitorRunning'] == expected:
                    return value
            except (OSError, ValueError):
                pass
            time.sleep(0.05)
        self.fail(f'daemon did not reach busy={expected}')

    def test_daemon_acquires_and_releases_only_for_live_turns(self):
        fake = self.root / 'systemd-inhibit'
        fake.write_text('#!/bin/sh\nexec sleep 1000\n')
        fake.chmod(0o755)
        env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ['PATH'])
        daemon = subprocess.Popen([sys.executable, str(SCRIPT), '--daemon', '--proc-root', str(self.proc),
                                   '--state-dir', str(self.root / 'state'), '--interval', '0.05'], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.addCleanup(lambda: daemon.poll() is None and daemon.kill())
        self.wait_status(False)
        self.event('task_started')
        self.wait_status(True)
        self.event('task_complete')
        self.wait_status(False)
        self.event('task_started', turn='two')
        self.wait_status(True)
        self.event('turn_aborted', turn='two')
        self.wait_status(False)
        self.event('task_started', turn='three')
        self.wait_status(True)
        (self.proc / '100/fd/3').unlink()
        self.wait_status(False)
        (self.proc / '100/fd/3').symlink_to(self.log)
        self.wait_status(True)
        daemon.terminate()
        _, stderr = daemon.communicate(timeout=5)
        self.assertEqual(daemon.returncode, 0, stderr.decode())
        self.assertFalse((self.root / 'state/status.json').exists())


if __name__ == '__main__':
    unittest.main()
