import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'screens/splash_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();





void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
    await NotificationService().initialize();
  } catch (e) {
    print("⚠️ [RIDER] Firebase initialization failed: $e");
    print("   Make sure google-services.json is present in android/app/");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'SRS User',
              theme: ThemeData(
                primarySwatch: Colors.blue,
                useMaterial3: true,
                textTheme: GoogleFonts.dmSansTextTheme(
                  Theme.of(context).textTheme,
                ),
                primaryTextTheme: GoogleFonts.dmSansTextTheme(
                  Theme.of(context).primaryTextTheme,
                ),
                scaffoldBackgroundColor: const Color(0xFF10223D),
                pageTransitionsTheme: PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              home: const SplashScreen(),
              navigatorKey: navigatorKey,
              showPerformanceOverlay: false,
            );
          },
        );
      },
    );
  }
}
