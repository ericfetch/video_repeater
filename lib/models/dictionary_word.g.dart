// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dictionary_word.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DictionaryWordAdapter extends TypeAdapter<DictionaryWord> {
  @override
  final int typeId = 31;

  @override
  DictionaryWord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DictionaryWord(
      word: fields[0] as String,
      partOfSpeech: fields[1] as String?,
      definition: fields[2] as String?,
      rank: fields[3] as int?,
      isVocabulary: fields[4] as bool,
      phonetic: fields[5] as String?,
      cefr: fields[6] as String?,
      extraInfo: (fields[7] as Map?)?.cast<String, dynamic>(),
      isFamiliar: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, DictionaryWord obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.word)
      ..writeByte(1)
      ..write(obj.partOfSpeech)
      ..writeByte(2)
      ..write(obj.definition)
      ..writeByte(3)
      ..write(obj.rank)
      ..writeByte(4)
      ..write(obj.isVocabulary)
      ..writeByte(5)
      ..write(obj.phonetic)
      ..writeByte(6)
      ..write(obj.cefr)
      ..writeByte(7)
      ..write(obj.extraInfo)
      ..writeByte(8)
      ..write(obj.isFamiliar);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryWordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
