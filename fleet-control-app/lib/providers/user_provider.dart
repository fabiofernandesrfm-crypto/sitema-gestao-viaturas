import 'package:flutter/material.dart';
import '../models/user_model.dart';

class UserProvider extends ChangeNotifier {
  String _email = '';
  String _password = '';
  UserModel? _user;
  bool _showPassword = false;

  String get email => _email;
  String get password => _password;
  UserModel? get user => _user;
  bool get showPassword => _showPassword;
  set showPassword(bool value) {
    _showPassword = value;
    notifyListeners();
  }

  set email(String value) {
    _email = value;
    notifyListeners();
  }

  set password(String value) {
    _password = value;
    notifyListeners();
  }

  set user(UserModel? value) {
    _user = value;
    notifyListeners();
  }
}