// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vocabulary_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VocabularyWordAdapter extends TypeAdapter<VocabularyWord> {
  @override
  final int typeId = 4;

  @override
  VocabularyWord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VocabularyWord(
      word: fields[0] as String,
      context: fields[1] as String,
      addedTime: fields[2] as DateTime,
      videoName: fields[3] as String,
    );
  }

  @override
  void write(BinaryWriter writer, VocabularyWord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.word)
      ..writeByte(1)
      ..write(obj.context)
      ..writeByte(2)
      ..write(obj.addedTime)
      ..writeByte(3)
      ..write(obj.videoName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabularyWordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class VocabularyListAdapter extends TypeAdapter<VocabularyList> {
  @override
  final int typeId = 5;

  @override
  VocabularyList read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VocabularyList(
      videoName: fields[0] as String,
      words: (fields[1] as List).cast<VocabularyWord>(),
    );
  }

  @override
  void write(BinaryWriter writer, VocabularyList obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.videoName)
      ..writeByte(1)
      ..write(obj.words);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VocabularyListAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
