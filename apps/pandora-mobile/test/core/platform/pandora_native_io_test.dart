import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/platform/pandora_native_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pandora/native_io');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('selected contact requires a usable phone number', () {
    expect(
      () => PandoraPhoneContactSelection.fromMap(<Object?, Object?>{
        'displayName': 'Maria',
        'phoneNumber': '',
      }),
      throwsFormatException,
    );
  });

  test('selected contact normalizes returned system values', () {
    final selection = PandoraPhoneContactSelection.fromMap(<Object?, Object?>{
      'displayName': ' Maria ',
      'phoneNumber': ' 0917 555 0123 ',
    });
    expect(selection.displayName, 'Maria');
    expect(selection.phoneNumber, '0917 555 0123');
  });

  test('text attachment comes only from the bounded native document picker',
      () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      observed = call;
      return <String, Object?>{
        'name': ' notes.md ',
        'mimeType': 'text/markdown',
        'text': '# Notes\nSafe text',
      };
    });

    final attachment = await PandoraNativeIo.pickTextAttachment();
    expect(observed?.method, 'pickTextDocument');
    expect(attachment?.name, 'notes.md');
    expect(attachment?.mimeType, 'text/markdown');
    expect(attachment?.text, '# Notes\nSafe text');
  });

  test('save export delegates bytes to an explicit native save picker',
      () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      observed = call;
      return true;
    });

    final saved = await PandoraNativeIo.saveBinaryDocument(
      name: 'evidence.zip',
      mimeType: 'application/zip',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    expect(saved, isTrue);
    expect(observed?.method, 'saveBinaryDocument');
    final arguments = observed?.arguments as Map<Object?, Object?>;
    expect(arguments['name'], 'evidence.zip');
    expect(arguments['mimeType'], 'application/zip');
    expect(arguments.containsKey('path'), isFalse);
    expect(arguments.containsKey('uri'), isFalse);
  });

  test('photo selection uses the bounded native image picker', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickPhoto');
      return <String, Object?>{
        'name': 'photo.jpg',
        'mimeType': 'image/jpeg',
        'dataBase64': 'AQID',
      };
    });
    final photo = await PandoraNativeIo.pickPhoto();
    expect(photo?.name, 'photo.jpg');
    expect(photo?.mimeType, 'image/jpeg');
    expect(photo?.dataBase64, 'AQID');
  });
}
