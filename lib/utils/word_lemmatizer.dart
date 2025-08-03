import 'package:stemmer/stemmer.dart';
import 'package:lemmatizerx/lemmatizerx.dart';

/// 词形还原模式
enum LemmatizationMode {
  /// 关闭词形还原，保持原词
  off,
  /// 简单模式，仅处理明显的复数和时态
  simple,
  /// 精确模式，使用先进的词形还原算法
  precise,
}

/// 改进的词形还原工具类
class ImprovedWordLemmatizer {
  static final PorterStemmer _stemmer = PorterStemmer();
  static final Lemmatizer _precisionLemmatizer = Lemmatizer();
  
  // 简单模式的安全规则 - 只处理明显正确的情况
  static final Map<String, String> _safeIrregularVerbs = {
    'was': 'be',
    'were': 'be',
    'been': 'be',
    'had': 'have',
    'has': 'have',
    'did': 'do',
    'done': 'do',
    'went': 'go',
    'gone': 'go',
    'made': 'make',
    'said': 'say',
    'took': 'take',
    'taken': 'take',
    'came': 'come',
    'saw': 'see',
    'seen': 'see',
    'knew': 'know',
    'known': 'know',
    'got': 'get',
    'gotten': 'get',
    'gave': 'give',
    'given': 'give',
    'found': 'find',
    'thought': 'think',
    'told': 'tell',
    'ran': 'run',
    'ate': 'eat',
    'eaten': 'eat',
  };
  
  // 简单模式的安全复数规则
  static final Map<String, String> _safeIrregularNouns = {
    'men': 'man',
    'women': 'woman',
    'children': 'child',
    'people': 'person',
    'mice': 'mouse',
    'teeth': 'tooth',
    'feet': 'foot',
  };
  
  // 不应该被还原的单词（它们本身就是词根）
  static final Set<String> _doNotLemmatize = {
    'news', 'class', 'glass', 'bass', 'mass', 'pass', 'grass', 'brass',
    'address', 'process', 'success', 'access', 'express', 'dress',
    'stress', 'press', 'progress', 'business', 'witness', 'fitness',
    'this', 'thus', 'plus', 'yes', 'less', 'unless', 'endless',
    'regardless', 'nevertheless', 'consensus', 'analysis', 'basis',
    'crisis', 'diagnosis', 'emphasis', 'hypothesis', 'oasis', 'synthesis',
    'thanks', 'perhaps', 'mathematics', 'physics', 'graphics', 'politics',
    'economics', 'athletics', 'statistics', 'tactics', 'dynamics',
    'its', 'his', 'hers', 'ours', 'yours', 'theirs',
    'always', 'sometimes', 'nowadays', 'towards', 'afterwards',
  };

  /// 根据指定模式对单词进行词形还原
  static String lemmatize(String word, LemmatizationMode mode) {
    if (word.isEmpty) return word;
    
    final lowercaseWord = word.toLowerCase();
    
    switch (mode) {
      case LemmatizationMode.off:
        return lowercaseWord;
        
      case LemmatizationMode.simple:
        return _simpleLemmatize(lowercaseWord);
        
      case LemmatizationMode.precise:
        return _preciseLemmatize(lowercaseWord);
    }
  }
  
  /// 简单模式：只处理明显正确的情况
  static String _simpleLemmatize(String word) {
    // 检查是否不应该被还原
    if (_doNotLemmatize.contains(word)) {
      return word;
    }
    
    // 检查不规则动词
    if (_safeIrregularVerbs.containsKey(word)) {
      return _safeIrregularVerbs[word]!;
    }
    
    // 检查不规则名词
    if (_safeIrregularNouns.containsKey(word)) {
      return _safeIrregularNouns[word]!;
    }
    
    // 简单的规则复数处理
    if (word.length > 3) {
      // 处理明显的复数
      if (word.endsWith('ies') && !word.endsWith('ries') && !word.endsWith('ties')) {
        return word.substring(0, word.length - 3) + 'y';
      }
      
      // 处理ed结尾的明显过去式
      if (word.endsWith('ed') && word.length > 4) {
        final stem = word.substring(0, word.length - 2);
        // 只处理明显的情况
        if (stem.endsWith('walk') || stem.endsWith('talk') || stem.endsWith('work') ||
            stem.endsWith('play') || stem.endsWith('stay') || stem.endsWith('look')) {
          return stem;
        }
      }
      
      // 处理ing结尾的现在分词（保守处理）
      if (word.endsWith('ing') && word.length > 5) {
        final stem = word.substring(0, word.length - 3);
        // 只处理明显的情况
        if (stem.endsWith('walk') || stem.endsWith('talk') || stem.endsWith('work') ||
            stem.endsWith('play') || stem.endsWith('look') || stem.endsWith('help')) {
          return stem;
        }
      }
      
      // 处理简单的s复数
      if (word.endsWith('s') && !word.endsWith('ss') && !word.endsWith('us') && 
          !word.endsWith('is') && word.length > 3) {
        return word.substring(0, word.length - 1);
      }
    }
    
    return word;
  }
  
  /// 精确模式：使用高级词形还原算法
  static String _preciseLemmatize(String word) {
    // 检查是否不应该被还原
    if (_doNotLemmatize.contains(word)) {
      return word;
    }
    
    try {
      // 尝试作为名词进行词形还原
      final nounLemma = _precisionLemmatizer.lemma(word, POS.NOUN);
      if (nounLemma.lemmasFound && nounLemma.lemmas.isNotEmpty) {
        return nounLemma.lemmas.first;
      }
      
      // 尝试作为动词进行词形还原
      final verbLemma = _precisionLemmatizer.lemma(word, POS.VERB);
      if (verbLemma.lemmasFound && verbLemma.lemmas.isNotEmpty) {
        return verbLemma.lemmas.first;
      }
      
      // 尝试作为形容词进行词形还原
      final adjLemma = _precisionLemmatizer.lemma(word, POS.ADJ);
      if (adjLemma.lemmasFound && adjLemma.lemmas.isNotEmpty) {
        return adjLemma.lemmas.first;
      }
      
      // 尝试作为副词进行词形还原
      final advLemma = _precisionLemmatizer.lemma(word, POS.ADV);
      if (advLemma.lemmasFound && advLemma.lemmas.isNotEmpty) {
        return advLemma.lemmas.first;
      }
      
    } catch (e) {
      // 如果精确模式失败，回退到简单模式
      return _simpleLemmatize(word);
    }
    
    // 如果所有尝试都失败，返回原词
    return word;
  }
  
  /// 获取模式描述
  static String getModeDescription(LemmatizationMode mode) {
    switch (mode) {
      case LemmatizationMode.off:
        return '关闭 - 保持原词';
      case LemmatizationMode.simple:
        return '简单 - 处理明显变化';
      case LemmatizationMode.precise:
        return '精确 - 使用高级算法';
    }
  }
}

/// 简化的词形还原工具类，直接使用最先进的算法
class WordLemmatizer {
  /// 直接使用最先进的精确模式
  static String lemmatize(String word) {
    return ImprovedWordLemmatizer.lemmatize(word, LemmatizationMode.precise);
  }
}  