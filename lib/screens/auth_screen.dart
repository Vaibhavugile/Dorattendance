import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import 'dart:math' as math;

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool isLogin = true;
  final emailC = TextEditingController();
  final passC = TextEditingController();
  final nameC = TextEditingController();
  String? error;

  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    emailC.dispose(); passC.dispose(); nameC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Clear previous error
    setState(() => error = null);

    final auth = Provider.of<AuthService>(context, listen: false);

    if (isLogin) {
      final err = await auth.signIn(emailC.text.trim(), passC.text.trim());
      if (err != null) {
        setState(() => error = err);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $err')));
      } else {
        // success
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged in successfully')));
        // optional: clear fields
        passC.clear();
      }
    } else {
      final err = await auth.signUp(nameC.text.trim(), emailC.text.trim(), passC.text.trim());
      if (err != null) {
        setState(() => error = err);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign up failed: $err')));
      } else {
        // success
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created')));
        // clear fields
        nameC.clear();
        emailC.clear();
        passC.clear();
        // optionally switch to login view
        setState(() => isLogin = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Animated background shape
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                return CustomPaint(
                  painter: _BackgroundPainter(_anim.value),
                );
              },
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text('DOR', style: GoogleFonts.poppins(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Attendance for your team', style: GoogleFonts.inter(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 28),

                  // Card with form
                  _AuthCard(
                    isLogin: isLogin,
                    nameC: nameC,
                    emailC: emailC,
                    passC: passC,
                    onToggle: () => setState(() => isLogin = !isLogin),
                    onSubmit: _submit,
                    error: error,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCard extends StatefulWidget {
  final bool isLogin;
  final TextEditingController nameC, emailC, passC;
  final VoidCallback onToggle;
  final Future<void> Function() onSubmit;
  final String? error;
  const _AuthCard({Key? key, required this.isLogin, required this.nameC, required this.emailC, required this.passC, required this.onToggle, required this.onSubmit, this.error}) : super(key: key);

  @override
  State<_AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends State<_AuthCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _elevationAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _elevationAnim = Tween<double>(begin: 4, end: 14).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withOpacity(0.75),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0,8))],
        ),
        width: math.min(560, MediaQuery.of(context).size.width * 0.95),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.isLogin ? 'Welcome back' : 'Create account', style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: widget.onToggle,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: widget.isLogin
                        ? Chip(label: Text('Sign up', style: TextStyle(color: Colors.black)), backgroundColor: Colors.amber, key: const ValueKey('signup'))
                        : Chip(label: Text('Login', style: TextStyle(color: Colors.white)), backgroundColor: Colors.indigo, key: const ValueKey('login')),
                  ),
                )
              ],
            ),
            const SizedBox(height: 18),

            if (!widget.isLogin)
              _buildTextField('Full name', widget.nameC),

            _buildTextField('Email', widget.emailC, keyboard: TextInputType.emailAddress),
            _buildTextField('Password', widget.passC, obscure: true),
            const SizedBox(height: 12),

            if (widget.error != null)
              Text(widget.error!, style: const TextStyle(color: Colors.redAccent)),

            const SizedBox(height: 6),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: auth.isLoading ? null : () async { await widget.onSubmit(); },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: auth.isLoading
                      ? const SizedBox(key: ValueKey('loader'), height: 18, width: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                      : Text(widget.isLogin ? 'Login' : 'Create account', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('By continuing, you agree to our', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                TextButton(onPressed: () {}, child: const Text('Terms'))
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController c, {bool obscure = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.white.withOpacity(0.04),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double t;
  _BackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // big rotating gradient blob
    final center = Offset(size.width * 0.2, size.height * 0.2);
    final r = size.width * 0.8;
    final angle = t * 2 * math.pi;
    final gradient = RadialGradient(colors: [Color(0xFF6D28D9), Color(0xFF0EA5E9)], stops: [0.0, 1.0]);
    paint.shader = gradient.createShader(Rect.fromCircle(center: center.translate(math.cos(angle) * 40, math.sin(angle) * 40), radius: r));
    canvas.drawCircle(center, r, paint);

    // smaller subtle shapes
    final p2 = Paint()..color = Colors.white.withOpacity(0.02);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), size.width * 0.25, p2);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.85), size.width * 0.18, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
