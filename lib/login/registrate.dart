
// lib/login/registrate.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/telescope_lottie.dart';
import '../utils/validators.dart';
import '../services/auth_service.dart';

class RegistratePage extends StatefulWidget {
  const RegistratePage({super.key});

  @override
  State<RegistratePage> createState() => _RegistratePageState();
}

class _RegistratePageState extends State<RegistratePage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return WillPopScope(
      onWillPop: () async {
        context.go('/login');
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/login.png', fit: BoxFit.cover),

            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.06,
                  vertical: screenHeight * 0.02,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: screenWidth * 0.6,
                          height: screenWidth * 0.6,
                          child: const TelescopeLottie(),
                        ),
                      ),

                      _buildTextField(
                        controller: _emailController,
                        hintText: 'Correo electrónico',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final String? base = Validators.validateEmail(value);
                          if (base != null) return base;
                          if (AuthService.instance.isEmailRegistered(
                            value!.trim(),
                          )) {
                            return 'El correo ya está registrado';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: screenHeight * 0.025),
                      _buildTextField(
                        controller: _usernameController,
                        hintText: 'Nombre de usuario',
                        validator: (value) {
                          final String? base = Validators.validateUsername(
                            value,
                          );
                          if (base != null) return base;
                          if (AuthService.instance.isUsernameTaken(
                            value!.trim(),
                          )) {
                            return 'El nombre de usuario ya está en uso';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: screenHeight * 0.025),
                      _buildTextField(
                        controller: _passwordController,
                        hintText: 'Contraseña',
                        obscureText: !_isPasswordVisible,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white60,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        validator: Validators.validateRegisterPassword,
                      ),
                      SizedBox(height: screenHeight * 0.025),
                      _buildTextField(
                        controller: _confirmPasswordController,
                        hintText: 'Confirmar contraseña',
                        obscureText: !_isConfirmPasswordVisible,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white60,
                          ),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible =
                                  !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor confirma tu contraseña';
                          }
                          if (value != _passwordController.text) {
                            return 'Las contraseñas no coinciden';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              try {
                                await AuthService.instance.register(
                                  emailRaw: _emailController.text,
                                  usernameRaw: _usernameController.text,
                                  password: _passwordController.text,
                                );
                                if (!context.mounted) return;
                                context.go('/home');
                              } on AuthException catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: const Color(0xFF33FFE6),
                            padding: EdgeInsets.symmetric(
                              vertical: screenHeight * 0.02,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Crear cuenta',
                            style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.005),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            context.push('/login');
                          },
                          child: Text(
                            '¿Ya tienes cuenta? Inicia sesión',
                            style: TextStyle(
                              color: Colors.yellow,
                              fontSize: screenWidth * 0.045,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                    ],
                  ),
                ),
              ),
            ),

            /// Flecha de retroceso al frente
            Positioned(
              top: screenHeight * 0.02,
              left: screenWidth * 0.02,
              child: SafeArea(
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back,
                    color: Colors.white.withOpacity(0.9),
                    size: screenWidth * 0.08,
                  ),
                  onPressed: () {
                    context.go('/login');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: Colors.white, fontSize: screenWidth * 0.04),
        keyboardType: keyboardType,
        obscureText: obscureText,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: Colors.white,
            fontSize: screenWidth * 0.04,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.04,
            vertical: screenHeight * 0.02,
          ),
        ),
        validator: validator,
      ),
    );
  }
}