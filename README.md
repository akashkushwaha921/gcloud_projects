Building a Flutter application that manages Google Cloud SDK, executes shell scripts on Cloud Shell, and forwards ports locally is a complex but achievable task. The key is understanding that `gcloud alpha cloud-shell ssh` is designed for interactive SSH sessions, and automating it requires careful handling of authentication and process management. Below is a complete guide with Dart code for each component.

## 🧱 Project Setup & Dependencies

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  path_provider: ^2.1.1
  url_launcher: ^6.2.1
```

## 📦 1. Download & Extract gcloud SDK (Linux ARM)

Create a `GCloudInstaller` class that downloads the tarball and extracts it to a local directory.

```dart
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GCloudInstaller {
  static const String _sdkUrl =
      'https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm.tar.gz';

  /// Downloads the tarball and extracts it.
  /// Returns the path to the gcloud binary.
  static Future<String> installGCloud({void Function(double)? onProgress}) async {
    final appDir = await getApplicationSupportDirectory();
    final sdkDir = Directory('${appDir.path}/google-cloud-sdk');
    final gcloudBin = '${sdkDir.path}/bin/gcloud';

    if (await File(gcloudBin).exists()) {
      return gcloudBin; // Already installed
    }

    // 1. Download tarball
    final tarballPath = '${appDir.path}/gcloud.tar.gz';
    final response = await http.Client().send(
      http.Request('GET', Uri.parse(_sdkUrl)),
    );
    final total = response.contentLength ?? 0;
    var received = 0;

    final sink = File(tarballPath).openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received / total);
    }
    await sink.close();

    // 2. Extract with tar (Linux/macOS)
    final tarResult = await Process.run(
      'tar',
      ['-xzf', tarballPath, '-C', appDir.path],
      runInShell: true,
    );
    if (tarResult.exitCode != 0) {
      throw Exception('Extraction failed: ${tarResult.stderr}');
    }

    // 3. Run gcloud init (non-interactive)
    await Process.run(
      gcloudBin,
      ['init', '--console-only', '--skip-diagnostics'],
      runInShell: true,
    );

    return gcloudBin;
  }
}
```

This uses `http` for streaming download and `tar` to extract, which is available on Linux ARM. The `gcloud init` step prepares the SDK for first use.

## 🔐 2. Authentication with Authorization Link

`gcloud auth login --no-browser` prints a URL that the user must open in a browser. You can capture that URL, launch it with `url_launcher`, and then pass the authorization code back to the process.

```dart
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class GCloudAuth {
  /// Runs `gcloud auth login --no-browser`.
  /// Extracts the URL, opens it, and returns the auth code entered by the user.
  static Future<void> login(String gcloudPath) async {
    final process = await Process.start(
      gcloudPath,
      ['auth', 'login', '--no-browser', '--quiet'],
      runInShell: true,
    );

    String? authUrl;
    final urlRegex = RegExp(r'https://accounts\.google\.com/[^\s]+');

    // Read stdout line by line to find the URL
    await for (final line in process.stdout
        .transform(SystemEncoding().decoder)
        .transform(const LineSplitter())) {
      print('gcloud: $line');
      if (authUrl == null) {
        final match = urlRegex.firstMatch(line);
        if (match != null) {
          authUrl = match.group(0);
          // Open the URL in the system browser
          await launchUrl(Uri.parse(authUrl!), mode: LaunchMode.externalApplication);
        }
      }
    }

    // Wait for the process to exit (the user will paste the code in the terminal)
    // In a real app, you would provide a text field to input the code and write it to process.stdin.
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('gcloud auth login failed with code $exitCode');
    }
  }
}
```

`gcloud auth login --no-browser` prints the authorization URL and waits for the user to paste the code back. In a Flutter UI, you would show a dialog to collect the code and then write it to `process.stdin`.

## 🖥️ 3. Running Shell Scripts on Cloud Shell

Use `gcloud cloud-shell ssh --command=...` to execute a remote command. The `--authorize-session` flag ensures the session is authorized for subsequent gcloud commands.

```dart
class CloudShellRunner {
  /// Runs a shell script (as a string) on Cloud Shell.
  /// Returns the combined stdout + stderr.
  static Future<String> runScript({
    required String gcloudPath,
    required String script,
    bool authorize = true,
  }) async {
    final args = <String>[
      'alpha', 'cloud-shell', 'ssh',
      '--command', script,
    ];
    if (authorize) {
      args.add('--authorize-session');
    }

    final result = await Process.run(
      gcloudPath,
      args,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Cloud Shell command failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return result.stdout.toString();
  }
}
```

`gcloud alpha cloud-shell ssh --command=COMMAND` runs a command and exits, and `--authorize-session` sends OAuth credentials to the session so that subsequent `gcloud`/`gsutil` calls work without re-auth.

### Example: Email Automation Script

```dart
final emailScript = '''
#!/bin/bash
echo "Sending email via Cloud Shell..."
# Your email automation logic here (e.g., using sendmail, python, etc.)
python3 -c "
import smtplib
# ... your email code ...
print('Email sent')
"
''';

final output = await CloudShellRunner.runScript(
  gcloudPath: gcloudPath,
  script: emailScript,
);
print(output);
```

## 🔗 4. Port Forwarding (Local Link Forwarding)

Forward a remote port on Cloud Shell to a local port using the `--ssh-flag` with `-L`. Then launch the local URL.

```dart
class PortForwarder {
  /// Starts a background SSH process that forwards [remotePort] on Cloud Shell
  /// to [localPort] on the local machine.
  static Future<Process> forwardPort({
    required String gcloudPath,
    required int localPort,
    required int remotePort,
  }) async {
    final process = await Process.start(
      gcloudPath,
      [
        'alpha', 'cloud-shell', 'ssh',
        '--ssh-flag=-L $localPort:localhost:$remotePort',
        '--authorize-session',
      ],
      runInShell: true,
    );

    // Optionally listen to stdout/stderr for debugging
    process.stdout.listen((data) => print('SSH: ${String.fromCharCodes(data)}'));
    process.stderr.listen((data) => print('SSH ERR: ${String.fromCharCodes(data)}'));

    return process; // Keep this process alive while forwarding is needed
  }

  /// Opens the forwarded local URL in the system browser.
  static Future<void> openLocalUrl(int localPort) async {
    final url = Uri.parse('http://localhost:$localPort');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
```

The `--ssh-flag="-L LOCAL:localhost:REMOTE"` syntax is the standard SSH port-forwarding flag, and `gcloud cloud-shell ssh` passes it through.

### Usage Example

```dart
// Forward Cloud Shell port 8080 to local port 8080
final sshProcess = await PortForwarder.forwardPort(
  gcloudPath: gcloudPath,
  localPort: 8080,
  remotePort: 8080,
);

// Give the tunnel a moment to establish
await Future.delayed(const Duration(seconds: 3));

// Open the local link
await PortForwarder.openLocalUrl(8080);

// ... later, kill the tunnel ...
// sshProcess.kill();
```

## 🧩 5. Putting It All Together (Flutter UI Skeleton)

```dart
class CloudShellManager {
  String? _gcloudPath;

  Future<void> initialize() async {
    _gcloudPath = await GCloudInstaller.installGCloud(
      onProgress: (p) => print('Download: ${(p * 100).toStringAsFixed(1)}%'),
    );
    await GCloudAuth.login(_gcloudPath!);
  }

  Future<String> runRemoteScript(String script) async {
    return CloudShellRunner.runScript(
      gcloudPath: _gcloudPath!,
      script: script,
    );
  }

  Future<Process> startPortForward(int local, int remote) async {
    return PortForwarder.forwardPort(
      gcloudPath: _gcloudPath!,
      localPort: local,
      remotePort: remote,
    );
  }
}
```

## ⚠️ Important Limitations & Considerations

1.  **“APK for Linux Architecture”**: If you mean an **Android APK that runs on Linux ARM devices** (e.g., Raspberry Pi with Android), Flutter can build an APK for `android-arm64` using `flutter build apk --target-platform android-arm64`. However, the `gcloud` CLI and `ssh` binary must exist in the Android environment — they don't by default. You would need to bundle a static `ssh` client and a compatible `gcloud` build (or use a pure-Dart SSH library like `dartssh2` instead of calling `gcloud`). If you mean a **Flutter Linux desktop app**, run `flutter build linux --target-platform linux-arm64` on an ARM64 Linux host.
2.  **Interactive SSH vs. `--command`**: The `gcloud alpha cloud-shell ssh` command is designed for interactive use. When you pass `--command`, it runs non-interactively. For persistent port forwarding, the process must stay alive; otherwise the tunnel closes.
3.  **Auth Code Handling**: In a real Flutter app, you cannot rely on the terminal for entering the auth code. You must capture `process.stdin` and provide a text field in the UI. The `--no-browser` flow prints the URL and then waits for the code on stdin.
4.  **Script Storage**: If you have many `.sh` files, store them in `assets/` and load them with `rootBundle.loadString('assets/scripts/email.sh')` before passing the content to `runScript`. You can also write them to a temp file and use `--command="bash /path/to/script.sh"`.
5.  **Cloud Shell Limits**: Cloud Shell sessions are ephemeral and have a 20-minute inactivity timeout. Port forwarding will drop if the session ends. For production workloads, consider using a Compute Engine VM instead.

## 📚 Summary

| Component | Dart API | Key Detail |
|---|---|---|
| SDK Download | `http.Client().send` + `tar` | Streams progress, extracts tarball |
| Auth | `Process.start` + `url_launcher` | `--no-browser` prints URL |
| Remote Script | `Process.run` with `--command` | `--authorize-session` for gcloud tools |
| Port Forward | `Process.start` with `--ssh-flag="-L"` | Standard SSH tunneling |

This architecture gives you a fully working Flutter app that installs gcloud, authenticates, runs arbitrary shell scripts on Cloud Shell, and forwards ports back to the local machine.
