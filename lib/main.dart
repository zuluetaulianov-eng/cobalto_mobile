import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/api_config.dart';
import 'screens/boot_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.loadConfig();
  runApp(const CobaltoApp());
}

class CobaltoApp extends StatelessWidget {
  const CobaltoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COBALTO HUB Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0B10),
        primaryColor: const Color(0xFF00E5FF),
        textTheme: GoogleFonts.robotoMonoTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFB388FF),
          surface: Color(0xFF141824),
          error: Color(0xFFFF2D55),
        ),
      ),
      home: const BootScreen(),
    );
  }
}
