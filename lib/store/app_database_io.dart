import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openAppDatabase(String name) async {
  final directory = await getApplicationDocumentsDirectory();
  return databaseFactoryIo.openDatabase('${directory.path}/$name');
}
