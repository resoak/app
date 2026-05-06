import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_settings_provider.dart';
import '../services/background_image_service.dart';

class LectureVaultBackground extends ConsumerWidget {
  const LectureVaultBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  static final BackgroundImageService _backgroundImageService =
      BackgroundImageService();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appSettingsProvider.select(
        (state) => state.asData?.value ?? AppSettings.defaults(),
      ),
    );
    final backgroundStyle = settings.backgroundStyle;
    final backgroundImagePath = settings.backgroundImagePath.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: backgroundImagePath.isEmpty
                ? _BackgroundFill(
                    key: ValueKey('style-${backgroundStyle.name}'),
                    style: backgroundStyle,
                  )
                : _ManagedImageBackground(
                    key: ValueKey('image-$backgroundImagePath'),
                    managedImagePath: backgroundImagePath,
                    fallbackStyle: backgroundStyle,
                    backgroundImageService: _backgroundImageService,
                  ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ManagedImageBackground extends StatefulWidget {
  const _ManagedImageBackground({
    super.key,
    required this.managedImagePath,
    required this.fallbackStyle,
    required this.backgroundImageService,
  });

  final String managedImagePath;
  final AppBackgroundStyle fallbackStyle;
  final BackgroundImageService backgroundImageService;

  @override
  State<_ManagedImageBackground> createState() =>
      _ManagedImageBackgroundState();
}

class _ManagedImageBackgroundState extends State<_ManagedImageBackground> {
  late Future<File?> _imageFile;

  @override
  void initState() {
    super.initState();
    _imageFile = _resolveImageFile();
  }

  @override
  void didUpdateWidget(covariant _ManagedImageBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.managedImagePath != widget.managedImagePath ||
        oldWidget.backgroundImageService != widget.backgroundImageService) {
      _imageFile = _resolveImageFile();
    }
  }

  Future<File?> _resolveImageFile() async {
    final resolvedPath = await widget.backgroundImageService
        .resolveManagedImagePath(widget.managedImagePath);
    final file = File(resolvedPath);
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _imageFile,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return _BackgroundFill(style: widget.fallbackStyle);
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundFill extends StatelessWidget {
  const _BackgroundFill({
    super.key,
    required this.style,
  });

  final AppBackgroundStyle style;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: switch (style) {
        AppBackgroundStyle.black => Colors.black,
        AppBackgroundStyle.white => Colors.white,
      },
    );
  }
}
