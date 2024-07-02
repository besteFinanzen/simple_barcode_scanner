import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:simple_barcode_scanner/enum.dart';
import 'package:webview_windows/webview_windows.dart';

import '../constant.dart';

class WindowBarcodeScanner extends StatefulWidget {
  final String lineColor;
  final String cancelButtonText;
  final bool isShowFlashIcon;
  final ScanType scanType;
  final Function(String) onScanned;
  final String? appBarTitle;
  final bool? centerTitle;
  final double? height;

  const WindowBarcodeScanner({
    super.key,
    required this.lineColor,
    required this.cancelButtonText,
    required this.isShowFlashIcon,
    required this.scanType,
    required this.onScanned,
    this.height,
    this.appBarTitle,
    this.centerTitle,
  });

  @override
  State<WindowBarcodeScanner> createState() => _WindowBarcodeScannerState();
}

class _WindowBarcodeScannerState extends State<WindowBarcodeScanner> {
  late final WebviewController controller;
  bool isPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    controller = WebviewController();
    if (widget.height != null) {
      controller.loadingState.listen((state) async {
        if (state == LoadingState.navigationCompleted) {
          var x = await controller.executeScript(
              "document.documentElement.scrollHeight");
          final double? y = double.tryParse(x.toString());
          if (y == null) return;
          await controller.executeScript("window.scrollTo(0,${(y/2).round()})");
          await controller.executeScript("document.body.style.overflow = 'hidden'");
          await controller.setZoomFactor(y/widget.height!);
        }
      });
    }
    _checkCameraPermission().then((granted) {
      debugPrint("Permission is $granted");
      isPermissionGranted = granted;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: initPlatformState(
        controller: controller,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return SizedBox(
            key: const ValueKey("_ScannerWebview"),
            child: Webview(
              height: widget.height,
              controller,
              permissionRequested: (url, permissionKind, isUserInitiated) =>
                  _onPermissionRequested(
                    url: url,
                    kind: permissionKind,
                    isUserInitiated: isUserInitiated,
                    context: context,
                    isPermissionGranted: isPermissionGranted,
                  ),
            ),
          );
        } else if (snapshot.hasError) {
          return Center(
            child: Text(snapshot.error.toString()),
          );
        }
        return const Center(
          child: CircularProgressIndicator(),
        );
      });
  }

  /// Checks if camera permission has already been granted
  Future<bool> _checkCameraPermission() async {
    return await Permission.camera.status.isGranted;
  }

  Future<WebviewPermissionDecision> _onPermissionRequested(
      {required String url,
      required WebviewPermissionKind kind,
      required bool isUserInitiated,
      required BuildContext context,
      required bool isPermissionGranted}) async {
    final WebviewPermissionDecision? decision;
    if (!isPermissionGranted) {
      decision = await showDialog<WebviewPermissionDecision>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Permission requested'),
          content:
              Text('\'${kind.name}\' permission is require to scan qr/barcode'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context, WebviewPermissionDecision.deny);
                isPermissionGranted = false;
              },
              child: const Text('Deny'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, WebviewPermissionDecision.allow);
                isPermissionGranted = true;
              },
              child: const Text('Allow'),
            ),
          ],
        ),
      );
    } else {
      decision = WebviewPermissionDecision.allow;
    }

    return decision ?? WebviewPermissionDecision.none;
  }

  String getAssetFileUrl({required String asset}) {
    final assetsDirectory = p.join(p.dirname(Platform.resolvedExecutable),
        'data', 'flutter_assets', asset);
    return Uri.file(assetsDirectory).toString();
  }

  Future<bool> initPlatformState(
      {required WebviewController controller}) async {
    String? barcodeNumber;

    try {
      await controller.initialize();
      await controller.loadUrl(getAssetFileUrl(asset: PackageConstant.barcodeFilePath));

      /// Listen to web to receive barcode
      controller.webMessage.listen((event) {
        if (event['methodName'] == "successCallback") {
          if (event['data'] is String &&
              event['data'].isNotEmpty &&
              barcodeNumber == null) {
            barcodeNumber = event['data'];
            widget.onScanned(barcodeNumber!);
            //controller.reload();
          }
        }
      });
    } catch (e) {
      rethrow;
    }
    return true;
  }
}
