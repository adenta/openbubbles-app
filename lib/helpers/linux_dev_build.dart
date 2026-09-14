import 'package:universal_io/io.dart';

const linuxDevBuildId = String.fromEnvironment('OPENBUBBLES_BUILD_ID', defaultValue: 'unpackaged');
String get desktopAppTitle => Platform.isLinux ? 'OpenBubbles Dev · $linuxDevBuildId' : 'OpenBubbles';
