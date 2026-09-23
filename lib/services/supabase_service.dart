import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const _url = 'https://rtobllrfgmnlsxixmfwj.supabase.co';
  static const _key =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0b2JsbHJmZ21ubHN4aXhtZndqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk1MDQ1MzYsImV4cCI6MjEwNTA4MDUzNn0.5AuNxLLbHByGGBVxbvkujHJ5VhUkFbNxRCkGW3ix3Y4';

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, anonKey: _key);
  }
}
