/// Choosing files to upload, or photographing a paper document with the camera.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../store.dart';

typedef Picked = ({String path, String name});

const uploadExts = ['pdf', 'docx', 'xlsx', 'csv', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'md'];
final supported = RegExp(r'\.(pdf|docx|xlsx|csv|png|jpe?g|webp|txt|md)$', caseSensitive: false);

Future<List<Picked>> pickFiles({bool multiple = true}) async {
  try {
    if (!multiple) {
      final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: uploadExts);
      return f?.path == null ? [] : [(path: f!.path!, name: f.name)];
    }
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: uploadExts);
    return [for (final f in files) if (f.path != null) (path: f.path!, name: f.name)];
  } catch (e) {
    store.toast("Couldn't open the file picker: $e");
    return [];
  }
}

Future<Picked?> takePhoto() async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 2600);
    if (x == null) return null;
    final name = 'Photo ${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.jpg';
    return (path: x.path, name: name);
  } catch (e) {
    store.toast("Couldn't open the camera: $e");
    return null;
  }
}

/// Asks where the file comes from: files on the phone, or a photo of a paper document.
Future<List<Picked>> pickSource(BuildContext context, {bool multiple = true}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.folder_open_outlined),
          title: Text(multiple ? 'Choose files' : 'Choose a file'),
          subtitle: const Text('PDF, Word, Excel, CSV, images or text'),
          onTap: () => Navigator.pop(ctx, 'files'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Take a photo'),
          subtitle: const Text('A paper letter or notice, read with OCR'),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
      ]),
    ),
  );
  if (choice == 'files') return pickFiles(multiple: multiple);
  if (choice == 'camera') {
    final p = await takePhoto();
    return p == null ? [] : [p];
  }
  return [];
}
