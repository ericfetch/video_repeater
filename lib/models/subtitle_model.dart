class SubtitleEntry {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  SubtitleEntry({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  Duration get duration => end - start;

  @override
  String toString() {
    return text;
  }
}

class SubtitleData {
  final List<SubtitleEntry> entries;

  SubtitleData({required this.entries});

  SubtitleEntry? getEntryAtTime(Duration position) {
    if (entries.isEmpty) return null;
    
    if (position < entries.first.start) return null;
    
    if (position > entries.last.end) return null;
    
    for (var entry in entries) {
      if (position >= entry.start && position < entry.end) {
        return entry;
      }
    }
    
    for (var entry in entries) {
      if (position == entry.end) {
        return entry;
      }
    }
    
    return null;
  }

  SubtitleEntry? getEntryByIndex(int index) {
    if (index >= 0 && index < entries.length) {
      return entries[index];
    }
    return null;
  }
} 