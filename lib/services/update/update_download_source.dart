enum UpdateDownloadSource {
  github;

  String get label => switch (this) {
    github => 'GitHub',
  };
}
