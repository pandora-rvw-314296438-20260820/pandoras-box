import 'pandora_local_store_contract.dart';
import 'pandora_local_store_stub.dart'
    if (dart.library.io) 'pandora_local_store_native.dart' as platform;

export 'pandora_local_data_policy.dart';
export 'pandora_local_store_contract.dart';

Future<PandoraLocalStore> openPandoraLocalStore() {
  return platform.openPandoraLocalStore();
}
