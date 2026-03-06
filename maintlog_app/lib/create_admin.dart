// ignore_for_file: avoid_print
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://ldxcqnornpwifxuqisau.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxkeGNxbm9ybnB3aWZ4dXFpc2F1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI3MjcxNzAsImV4cCI6MjA4ODMwMzE3MH0.op5hX8HwAMVuUlfcntqYcc1xrx9C-dQjcsXdAqIs4l8',
  );

  final supabase = Supabase.instance.client;

  try {
    final res = await supabase.auth.signUp(
      email: 'malgaroshy@ai.gg',
      password: 'Admin12341234',
    );
    print('Admin user created: ${res.user!.id}');
  } catch (e) {
    print('Failed to create admin user: \$e');
  }
}
