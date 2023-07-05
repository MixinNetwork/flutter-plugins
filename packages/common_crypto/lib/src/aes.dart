import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'common_crypto_bindings_generated.dart';
import 'tools.dart';

Uint8List _aesCrypt({
  required Uint8List key,
  required Uint8List data,
  required Uint8List iv,
  required bool encrypt,
}) {
  final cryptor = AesCryptor(
    encrypt: encrypt,
    key: key,
    iv: iv,
  );
  final output = <int>[];
  cryptor.update(data, (data) {
    output.addAll(data);
  });
  cryptor.finalize((data) {
    output.addAll(data);
  });
  return Uint8List.fromList(output);
}

Uint8List aesEncrypt({
  required Uint8List key,
  required Uint8List data,
  required Uint8List iv,
}) =>
    _aesCrypt(
      key: key,
      data: data,
      iv: iv,
      encrypt: true,
    );

Uint8List aesDecrypt({
  required Uint8List key,
  required Uint8List data,
  required Uint8List iv,
}) =>
    _aesCrypt(
      key: key,
      data: data,
      iv: iv,
      encrypt: false,
    );

class AesCryptor {
  final bool encrypt;

  final Uint8List key;
  final Uint8List iv;

  late Pointer<CCCryptor> _cryptorRef;

  AesCryptor({
    required this.encrypt,
    required this.key,
    required this.iv,
  }) {
    final cryptorRef = malloc<Pointer<CCCryptor>>();
    final keyPointer = key.pointer;
    final ivPointer = iv.pointer;
    // function call
    final status = bindings.CCCryptorCreate(
      encrypt ? kCCEncrypt : kCCDecrypt,
      kCCAlgorithmAES,
      kCCOptionPKCS7Padding,
      keyPointer.cast(),
      key.length,
      ivPointer.cast(),
      cryptorRef,
    );
    malloc.free(keyPointer);

    if (status != kCCSuccess) {
      throw Exception('CCCryptorCreate failed: $status');
    }
    _cryptorRef = cryptorRef.value;
    malloc.free(cryptorRef);
  }

  int outputDataCount(
    int inputDataCount, {
    required bool isFinal,
  }) =>
      bindings.CCCryptorGetOutputLength(
        _cryptorRef,
        inputDataCount,
        isFinal,
      );

  void update(
    Uint8List data,
    void Function(Uint8List data) onOutputData,
  ) {
    final outputSize = outputDataCount(data.length, isFinal: false);
    final outputData = malloc<Uint8>(outputSize);
    final dataOutMoved = malloc<Size>();

    final dataIn = data.pointer;
    final status = bindings.CCCryptorUpdate(
      _cryptorRef,
      dataIn.cast(),
      data.length,
      outputData.cast(),
      outputSize,
      dataOutMoved,
    );
    malloc.free(dataIn);
    final dataOutMovedValue = dataOutMoved.value;
    malloc.free(dataOutMoved);
    if (status != kCCSuccess) {
      throw Exception('CCCryptorUpdate failed: $status');
    }

    if (dataOutMovedValue == 0) {
      onOutputData(Uint8List(0));
    } else {
      final output = outputData.asTypedList(dataOutMovedValue);
      onOutputData(output);
    }
    malloc.free(outputData);
  }

  void finalize(void Function(Uint8List data) onData) {
    final outputSize = outputDataCount(0, isFinal: true);
    final outputData = malloc<Uint8>(outputSize);
    final dataOutMoved = malloc<Size>();

    final status = bindings.CCCryptorFinal(
      _cryptorRef,
      outputData.cast(),
      outputSize,
      dataOutMoved,
    );
    final dataOutMovedValue = dataOutMoved.value;
    malloc.free(dataOutMoved);
    if (status != kCCSuccess) {
      throw Exception('CCCryptorFinal failed: $status');
    }

    if (dataOutMovedValue == 0) {
      onData(Uint8List(0));
    } else {
      final output = outputData.asTypedList(dataOutMovedValue);
      onData(output);
    }
    malloc.free(outputData);
  }

  void dispose() {
    bindings.CCCryptorRelease(_cryptorRef);
  }
}
