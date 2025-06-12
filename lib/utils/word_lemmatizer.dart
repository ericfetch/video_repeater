import 'package:stemmer/stemmer.dart';

/// 词形还原工具类，用于将单词还原为基本形式
class WordLemmatizer {
  static final PorterStemmer _stemmer = PorterStemmer();
  
  // 常见的不规则动词过去式和过去分词映射
  static final Map<String, String> _irregularVerbs = {
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
    'became': 'become',
    'shown': 'show',
    'showed': 'show',
    'left': 'leave',
    'felt': 'feel',
    'brought': 'bring',
    'bought': 'buy',
    'meant': 'mean',
    'sent': 'send',
    'paid': 'pay',
    'built': 'build',
    'understood': 'understand',
    'kept': 'keep',
    'let': 'let',
    'put': 'put',
    'set': 'set',
    'ran': 'run',
    'sat': 'sit',
    'spoke': 'speak',
    'spoken': 'speak',
    'stood': 'stand',
    'won': 'win',
    'heard': 'hear',
    'held': 'hold',
    'met': 'meet',
    'lost': 'lose',
    'read': 'read',  // 相同拼写但发音不同
    'ate': 'eat',
    'eaten': 'eat',
    'flew': 'fly',
    'flown': 'fly',
    'grew': 'grow',
    'grown': 'grow',
    'drew': 'draw',
    'drawn': 'draw',
    'threw': 'throw',
    'thrown': 'throw',
    'knew': 'know',
    'known': 'know',
    'drove': 'drive',
    'driven': 'drive',
    'wrote': 'write',
    'written': 'write',
    'rode': 'ride',
    'ridden': 'ride',
    'rose': 'rise',
    'risen': 'rise',
    'chose': 'choose',
    'chosen': 'choose',
    'broke': 'break',
    'broken': 'break',
    'spoke': 'speak',
    'spoken': 'speak',
    'stole': 'steal',
    'stolen': 'steal',
    'froze': 'freeze',
    'frozen': 'freeze',
    'forgot': 'forget',
    'forgotten': 'forget',
    'swam': 'swim',
    'swum': 'swim',
    'began': 'begin',
    'begun': 'begin',
    'rang': 'ring',
    'rung': 'ring',
    'sang': 'sing',
    'sung': 'sing',
    'sank': 'sink',
    'sunk': 'sink',
    'drank': 'drink',
    'drunk': 'drink',
    'shrank': 'shrink',
    'shrunk': 'shrink',
    'sprang': 'spring',
    'sprung': 'spring',
    'swore': 'swear',
    'sworn': 'swear',
    'tore': 'tear',
    'torn': 'tear',
    'wore': 'wear',
    'worn': 'wear',
    'woke': 'wake',
    'woken': 'wake',
    'blew': 'blow',
    'blown': 'blow',
    'slept': 'sleep',
    'crept': 'creep',
    'wept': 'weep',
    'dealt': 'deal',
    'meant': 'mean',
    'dreamt': 'dream',
    'dreamed': 'dream',
    'leapt': 'leap',
    'leaped': 'leap',
    'felt': 'feel',
    'knelt': 'kneel',
    'kneeled': 'kneel',
    'sought': 'seek',
    'taught': 'teach',
    'caught': 'catch',
    'brought': 'bring',
    'bought': 'buy',
    'fought': 'fight',
    'thought': 'think',
    'dug': 'dig',
    'hung': 'hang',
    'stuck': 'stick',
    'struck': 'strike',
  };
  
  // 常见的不规则名词复数映射
  static final Map<String, String> _irregularNouns = {
    'men': 'man',
    'women': 'woman',
    'children': 'child',
    'people': 'person',
    'mice': 'mouse',
    'teeth': 'tooth',
    'feet': 'foot',
    'geese': 'goose',
    'oxen': 'ox',
    'knives': 'knife',
    'lives': 'life',
    'wives': 'wife',
    'shelves': 'shelf',
    'wolves': 'wolf',
    'leaves': 'leaf',
    'loaves': 'loaf',
    'thieves': 'thief',
    'potatoes': 'potato',
    'tomatoes': 'tomato',
    'heroes': 'hero',
    'echoes': 'echo',
    'analyses': 'analysis',
    'criteria': 'criterion',
    'phenomena': 'phenomenon',
    'data': 'datum',
    'media': 'medium',
    'cacti': 'cactus',
    'fungi': 'fungus',
    'alumni': 'alumnus',
    'vertices': 'vertex',
    'indices': 'index',
    'matrices': 'matrix',
    'appendices': 'appendix',
    'crises': 'crisis',
    'diagnoses': 'diagnosis',
    'hypotheses': 'hypothesis',
    'oases': 'oasis',
    'parentheses': 'parenthesis',
    'theses': 'thesis',
    'bases': 'basis',
    'axes': 'axis',
    'foci': 'focus',
    'nuclei': 'nucleus',
    'stimuli': 'stimulus',
    'syllabi': 'syllabus',
    'radii': 'radius',
    'bacteria': 'bacterium',
    'curricula': 'curriculum',
    'memoranda': 'memorandum',
    'strata': 'stratum',
    'larvae': 'larva',
    'antennae': 'antenna',
    'formulae': 'formula',
    'nebulae': 'nebula',
    'vertebrae': 'vertebra',
    'vitae': 'vita',
  };
  
  // 特殊处理的形容词，这些词以ed结尾但不应该被还原
  static final Set<String> _specialAdjectives = {
    'advanced',
    'aged',
    'alleged',
    'beloved',
    'blessed',
    'complicated',
    'confused',
    'detailed',
    'disappointed',
    'educated',
    'excited',
    'experienced',
    'interested',
    'limited',
    'motivated',
    'prepared',
    'qualified',
    'sophisticated',
    'surprised',
    'tired',
    'unexpected',
    'unbalanced',
    'undecided',
    'united',
    'unwanted',
    'used',
    'wicked',
  };
  
  // 特殊的ing形式单词映射
  static final Map<String, String> _specialIngForms = {
    'punting': 'punt',
    'hunting': 'hunt',
    'bunting': 'bunt',
    'shunting': 'shunt',
    'fronting': 'front',
    'counting': 'count',
    'mounting': 'mount',
    'accounting': 'account',
    'discounting': 'discount',
    'recounting': 'recount',
    'surmounting': 'surmount',
    'confronting': 'confront',
    'grunting': 'grunt',
    'stunting': 'stunt',
    'wanting': 'want',
    'planting': 'plant',
    'granting': 'grant',
    'slanting': 'slant',
    'chanting': 'chant',
    'ranting': 'rant',
    'panting': 'pant',
    'venting': 'vent',
    'denting': 'dent',
    'renting': 'rent',
    'tenting': 'tent',
    'inventing': 'invent',
    'preventing': 'prevent',
    'consenting': 'consent',
    'relenting': 'relent',
    'repenting': 'repent',
    'printing': 'print',
    'sprinting': 'sprint',
    'squinting': 'squint',
    'hinting': 'hint',
    'tinting': 'tint',
    'stinting': 'stint',
    'pointing': 'point',
    'jointing': 'joint',
    'anointing': 'anoint',
    'disappointing': 'disappoint',
    'lifting': 'lift',
    'shifting': 'shift',
    'drifting': 'drift',
    'gifting': 'gift',
    'sifting': 'sift',
    'listing': 'list',
    'twisting': 'twist',
    'existing': 'exist',
    'insisting': 'insist',
    'persisting': 'persist',
    'resisting': 'resist',
    'assisting': 'assist',
    'consisting': 'consist',
    'enlisting': 'enlist',
    'costing': 'cost',
    'posting': 'post',
    'hosting': 'host',
    'roasting': 'roast',
    'boasting': 'boast',
    'toasting': 'toast',
    'ghosting': 'ghost',
  };
  
  /// 将单词还原为基本形式
  /// 
  /// 处理流程：
  /// 1. 检查是否是特殊形容词
  /// 2. 检查是否是不规则动词或名词
  /// 3. 检查特殊的ing形式单词
  /// 4. 处理常见的后缀规则
  /// 5. 使用Porter词干提取算法（但避免过度还原）
  static String lemmatize(String word) {
    if (word.isEmpty) return word;
    
    // 转为小写
    final lowercaseWord = word.toLowerCase();
    
    // 检查是否是特殊形容词
    if (_specialAdjectives.contains(lowercaseWord)) {
      return lowercaseWord;
    }
    
    // 检查不规则动词
    if (_irregularVerbs.containsKey(lowercaseWord)) {
      return _irregularVerbs[lowercaseWord]!;
    }
    
    // 检查不规则名词
    if (_irregularNouns.containsKey(lowercaseWord)) {
      return _irregularNouns[lowercaseWord]!;
    }
    
    // 检查特殊的ing形式单词
    if (_specialIngForms.containsKey(lowercaseWord)) {
      return _specialIngForms[lowercaseWord]!;
    }
    
    // 处理常见的规则后缀
    if (lowercaseWord.endsWith('s') && !lowercaseWord.endsWith('ss') && !lowercaseWord.endsWith('ous') && !lowercaseWord.endsWith('ious')) {
      // 可能是复数形式或第三人称单数，但排除以ous/ious结尾的形容词
      return lowercaseWord.substring(0, lowercaseWord.length - 1);
    } else if (lowercaseWord.endsWith('es') && lowercaseWord.length > 3 && !lowercaseWord.endsWith('oes')) {
      // 处理以es结尾的复数，但排除does, goes等
      return lowercaseWord.substring(0, lowercaseWord.length - 2);
    } else if (lowercaseWord.endsWith('ies') && lowercaseWord.length > 3) {
      // 处理以y结尾变为ies的复数
      return lowercaseWord.substring(0, lowercaseWord.length - 3) + 'y';
    } else if (lowercaseWord.endsWith('ed') && lowercaseWord.length > 3) {
      // 处理过去式，但需要检查是否是形容词
      
      // 检查是否是常见的以ed结尾的形容词
      // 这里可以添加更多的启发式规则来判断
      if (lowercaseWord.endsWith('ated') || 
          lowercaseWord.endsWith('ized') || 
          lowercaseWord.endsWith('ised') ||
          lowercaseWord.startsWith('un') && lowercaseWord.length > 5) {
        // 可能是形容词，保持原样
        return lowercaseWord;
      }
      
      if (lowercaseWord.endsWith('ied')) {
        return lowercaseWord.substring(0, lowercaseWord.length - 3) + 'y';
      } else if (lowercaseWord.endsWith('eed')) {
        return lowercaseWord.substring(0, lowercaseWord.length - 1);
      } else {
        return lowercaseWord.substring(0, lowercaseWord.length - 2);
      }
    } else if (lowercaseWord.endsWith('ing') && lowercaseWord.length > 4) {
      // 处理现在分词
      final stem = lowercaseWord.substring(0, lowercaseWord.length - 3);
      
      if (lowercaseWord.length > 5 && _isDoubleConsonant(lowercaseWord.substring(lowercaseWord.length - 5, lowercaseWord.length - 3))) {
        // 双写辅音字母的情况，如running -> run
        return lowercaseWord.substring(0, lowercaseWord.length - 4);
      } else if (lowercaseWord.endsWith('ying')) {
        // 以y结尾的情况，如flying -> fly
        return lowercaseWord.substring(0, lowercaseWord.length - 4) + 'y';
      } else if (stem.endsWith('l') && !stem.endsWith('ll')) {
        // 处理以l结尾的词，如coddling -> coddle
        return stem + 'le';
      } else if (stem.endsWith('e')) {
        // 如果词干已经以e结尾，不需要添加e
        return stem;
      } else if (lowercaseWord.endsWith('nting')) {
        // 处理特殊情况，如punting -> punt
        return stem;
      } else {
        // 大多数情况下，需要添加e，如coming -> come, making -> make
        // 但有些词不需要，如sing -> sing, bring -> bring
        // 这里添加一些启发式规则来判断
        final noEWords = {
          'sing', 'bring', 'cling', 'fling', 'ring', 'spring', 'sting', 'swing', 
          'thing', 'wing', 'king', 'hunt', 'punt', 'grant', 'want', 'plant', 'slant',
          'print', 'sprint', 'hint', 'tint', 'list', 'twist', 'exist', 'insist',
          'resist', 'assist', 'persist', 'consist', 'cost', 'post', 'host'
        };
        
        if (noEWords.contains(stem) || stem.endsWith('nt') || stem.endsWith('st') || stem.endsWith('ft')) {
          return stem;
        }
        
        return stem + 'e';
      }
    } 
    
    // 对于其他情况，直接返回原词，避免使用Porter词干提取算法过度还原
    return lowercaseWord;
  }
  
  // 检查是否是双写的辅音字母
  static bool _isDoubleConsonant(String str) {
    if (str.length != 2) return false;
    final consonants = 'bcdfghjklmnpqrstvwxyz';
    return str[0] == str[1] && consonants.contains(str[0]);
  }
}  