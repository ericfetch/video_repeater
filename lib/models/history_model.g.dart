// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VideoHistoryAdapter extends TypeAdapter<VideoHistory> {
  @override
  final int typeId = 1;

  @override
  VideoHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VideoHistory(
      videoPath: fields[0] as String,
      subtitlePath: fields[1] as String,
      videoName: fields[2] as String,
      lastPosition: fields[3] as Duration,
      timestamp: fields[4] as DateTime,
      subtitleTimeOffset: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, VideoHistory obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.videoPath)
      ..writeByte(1)
      ..write(obj.subtitlePath)
      ..writeByte(2)
      ..write(obj.videoName)
      ..writeByte(3)
      ..write(obj.lastPosition)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.subtitleTimeOffset);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
