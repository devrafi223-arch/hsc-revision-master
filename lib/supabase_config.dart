// ===========================================================================
//  SUPABASE CONFIG — PLACEHOLDER VALUES (replace with the real project)
// ===========================================================================
//  Rafi must create a Supabase project (or give Arlo its URL + anon key)
//  and paste the real values below. Until then the app runs in LOCAL-ONLY
//  mode: SupabaseInit.initialize() sees the 'TODO' placeholders, skips
//  init, and the tracker keeps working fully offline.
//
//  ONLY the anon (publishable) key belongs in the app. NEVER put the
//  service_role key here — it bypasses Row Level Security and must live
//  only on a trusted server / Edge Function, never in client code.
// ===========================================================================

/// Supabase project connection values for HSC Revision Master.
class SupabaseConfig {
  /// Project URL, e.g. 'https://xyzcompany.supabase.co'.
  static const String url = 'https://jlhapvzrsckmldtdgeec.supabase.co';

  /// Anon (publishable) key from the Supabase dashboard (Project Settings
  /// → API). Safe to ship in the app — RLS still applies.
  static const String anonKey = 'sb_publishable_vTE3WQLU3ZFOGu78kcU32A_OydyhIeu';
}
