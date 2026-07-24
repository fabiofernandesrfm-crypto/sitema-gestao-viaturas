import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'providers/log_provider.dart';

void main() async {
  // Garante a inicialização correta para ler o armazenamento local
  WidgetsFlutterBinding.ensureInitialized();
  
  // Verifica se existe um usuário logado e se a sessão ainda é válida (menos de 2 horas)
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final int? loginTimestamp = prefs.getInt('loginTimestamp');
  
  Widget initialScreen = const LoginScreen();

  if (isLoggedIn && loginTimestamp != null) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    // 2 horas em milissegundos (2 * 60 * 60 * 1000 = 7200000)
    const twoHoursInMs = 7200000; 

    if (currentTime - loginTimestamp < twoHoursInMs) {
      // Sessão válida! Recupera os dados salvos localmente
      final nome = prefs.getString('nome') ?? 'Agente';
      final cargo = prefs.getString('cargo') ?? 'Agente'; // <--- Recupera o cargo salvo
      final bool isAdm = prefs.getBool('isAdm') ?? false; // <--- Recupera o status de Administrador
      final cpf = prefs.getString('cpf') ?? '';
      final email = prefs.getString('email') ?? '';
      
      final horaLoginMs = prefs.getInt('horaLoginTimestamp') ?? currentTime;
      final t = DateTime.fromMillisecondsSinceEpoch(horaLoginMs);
      final horaLogin = '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

      initialScreen = MainScreen(
        nome: nome,
        cargo: cargo,     // <--- Passa o cargo atualizado
        isAdm: isAdm,     // <--- Passa o status de administrador para filtrar os módulos
        cpf: cpf,
        email: email,
        horaLogin: horaLogin,
      );
    } else {
      // Sessão expirou, limpa os dados
      await prefs.clear();
    }
  }

  runApp(MyApp(initialScreen: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({Key? key, required this.initialScreen}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogProvider()),
      ],
      child: MaterialApp(
        title: 'SGV - Sistema de Gestão de Viaturas',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: initialScreen,
      ),
    );
  }
}