import 'dart:io';
import 'dart:typed_data';

/// Strips PNG-disguised headers from MPEG-TS segments (inherited from XgCartoonDownloader).
Uint8List stripPngDisguiseHeader(Uint8List data) {
  if (data.length >= 8 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4e &&
      data[3] == 0x47 &&
      data[4] == 0x0d &&
      data[5] == 0x0a &&
      data[6] == 0x1a &&
      data[7] == 0x0a) {
    int? tsOffset;
    final searchLimit =
        (data.length - 188 * 3) < 120 ? (data.length - 188 * 3) : 120;
    if (searchLimit > 8) {
      for (var offset = 8; offset < searchLimit; offset++) {
        if (data[offset] == 0x47 &&
            data[offset + 188] == 0x47 &&
            data[offset + 188 * 2] == 0x47) {
          tsOffset = offset;
          break;
        }
      }
    }
    tsOffset ??= (data.length >= 74 && data[73] == 0x47)
        ? 73
        : ((data.length >= 69 && data[68] == 0x47) ? 68 : null);
    if (tsOffset != null) {
      return Uint8List.sublistView(data, tsOffset);
    }
  }
  return data;
}

class _MediaSample {
  _MediaSample({
    required this.data,
    required this.pts,
    required this.dts,
    required this.isKeyFrame,
  });

  final Uint8List data;
  final int pts;
  final int dts;
  final bool isKeyFrame;
}

class _PesBuffer {
  final BytesBuilder builder = BytesBuilder(copy: false);
  int? pts;
  int? dts;
}

/// Pure-Dart lossless MPEG-TS (H.264 + AAC) to MP4 (ISO BMFF) remuxer.
/// Zero external binary dependencies; works identically on macOS, Linux, Windows, and Android.
class TsToMp4Remuxer {
  static const int _tsPacketSize = 188;
  static const int _syncByte = 0x47;

  static const List<int> _aacSampleRates = <int>[
    96000,
    88200,
    64000,
    48000,
    44100,
    32000,
    24000,
    22050,
    16000,
    12000,
    11025,
    8000,
    7350,
  ];

  /// Remuxes [tsFile] into [mp4File]. Returns true on success.
  static Future<bool> remux(File tsFile, File mp4File) async {
    try {
      final tsBytes = await tsFile.readAsBytes();
      final mp4Bytes = remuxBytes(tsBytes);
      if (mp4Bytes == null || mp4Bytes.isEmpty) return false;
      await mp4File.writeAsBytes(mp4Bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remuxes raw MPEG-TS bytes into MP4 bytes in memory.
  static Uint8List? remuxBytes(Uint8List tsBytes) {
    if (tsBytes.length < _tsPacketSize) return null;

    var offset = 0;
    while (offset + _tsPacketSize <= tsBytes.length &&
        tsBytes[offset] != _syncByte) {
      offset++;
    }
    if (offset + _tsPacketSize > tsBytes.length) return null;

    int? pmtPid;
    int? videoPid;
    int? audioPid;

    final videoPes = _PesBuffer();
    final audioPes = _PesBuffer();

    final videoSamples = <_MediaSample>[];
    final audioSamples = <_MediaSample>[];

    Uint8List? sps;
    Uint8List? pps;
    int audioObjType = 2; // AAC-LC
    int audioFreqIndex = 4; // 44100 Hz
    int audioChannels = 2;

    void flushVideoPes() {
      if (videoPes.builder.length == 0) return;
      final pesData = videoPes.builder.takeBytes();
      final pts = videoPes.pts ?? 0;
      final dts = videoPes.dts ?? pts;

      final nalus = _splitAnnexBNalus(pesData);
      if (nalus.isEmpty) return;

      final sampleBuilder = BytesBuilder(copy: false);
      var isKeyFrame = false;

      for (final nalu in nalus) {
        if (nalu.isEmpty) continue;
        final naluType = nalu[0] & 0x1F;
        if (naluType == 7) {
          sps ??= Uint8List.fromList(nalu);
        } else if (naluType == 8) {
          pps ??= Uint8List.fromList(nalu);
        } else if (naluType == 9) {
          // AUD: skip
        } else {
          if (naluType == 5) isKeyFrame = true;
          final len = nalu.length;
          sampleBuilder.add(<int>[
            (len >> 24) & 0xFF,
            (len >> 16) & 0xFF,
            (len >> 8) & 0xFF,
            len & 0xFF,
          ]);
          sampleBuilder.add(nalu);
        }
      }

      final avccData = sampleBuilder.takeBytes();
      if (avccData.isNotEmpty) {
        videoSamples.add(
          _MediaSample(
            data: avccData,
            pts: pts,
            dts: dts,
            isKeyFrame: isKeyFrame,
          ),
        );
      }
    }

    void flushAudioPes() {
      if (audioPes.builder.length == 0) return;
      final pesData = audioPes.builder.takeBytes();
      var basePts = audioPes.pts ?? 0;

      var pos = 0;
      while (pos + 7 <= pesData.length) {
        if (pesData[pos] != 0xFF || (pesData[pos + 1] & 0xF0) != 0xF0) {
          pos++;
          continue;
        }
        final protectionAbsent = (pesData[pos + 1] & 0x01) != 0;
        final headerLen = protectionAbsent ? 7 : 9;
        if (pos + headerLen > pesData.length) break;

        final frameLen = ((pesData[pos + 3] & 0x03) << 11) |
            (pesData[pos + 4] << 3) |
            ((pesData[pos + 5] & 0xE0) >> 5);
        if (frameLen < headerLen || pos + frameLen > pesData.length) break;

        audioObjType = ((pesData[pos + 2] >> 6) & 0x03) + 1;
        audioFreqIndex = (pesData[pos + 2] >> 2) & 0x0F;
        audioChannels = ((pesData[pos + 2] & 0x01) << 2) |
            ((pesData[pos + 3] >> 6) & 0x03);

        final rawFrame =
            Uint8List.sublistView(pesData, pos + headerLen, pos + frameLen);
        audioSamples.add(
          _MediaSample(
            data: rawFrame,
            pts: basePts,
            dts: basePts,
            isKeyFrame: true,
          ),
        );

        final sampleRate = audioFreqIndex < _aacSampleRates.length
            ? _aacSampleRates[audioFreqIndex]
            : 44100;
        basePts += (1024 * 90000) ~/ sampleRate;
        pos += frameLen;
      }
    }

    for (var pos = offset;
        pos + _tsPacketSize <= tsBytes.length;
        pos += _tsPacketSize) {
      if (tsBytes[pos] != _syncByte) continue;

      final pusi = (tsBytes[pos + 1] & 0x40) != 0;
      final pid = ((tsBytes[pos + 1] & 0x1F) << 8) | tsBytes[pos + 2];
      final afc = (tsBytes[pos + 3] >> 4) & 0x03;

      var payloadStart = pos + 4;
      if (afc == 2 || afc == 0) continue; // No payload
      if (afc == 3) {
        final afLen = tsBytes[payloadStart];
        payloadStart += 1 + afLen;
      }
      if (payloadStart >= pos + _tsPacketSize) continue;

      final payload =
          Uint8List.sublistView(tsBytes, payloadStart, pos + _tsPacketSize);

      if (pid == 0x0000) {
        pmtPid ??= _parsePat(payload, pusi);
        continue;
      }

      if (pmtPid != null && pid == pmtPid) {
        final parsed = _parsePmt(payload, pusi);
        if (parsed.$1 != null) videoPid ??= parsed.$1;
        if (parsed.$2 != null) audioPid ??= parsed.$2;
        continue;
      }

      if (videoPid != null && pid == videoPid) {
        if (pusi) {
          flushVideoPes();
          final parsedPes = _parsePesHeader(payload);
          videoPes.pts = parsedPes.pts;
          videoPes.dts = parsedPes.dts;
          videoPes.builder.add(parsedPes.payload);
        } else {
          videoPes.builder.add(payload);
        }
      } else if (audioPid != null && pid == audioPid) {
        if (pusi) {
          flushAudioPes();
          final parsedPes = _parsePesHeader(payload);
          audioPes.pts = parsedPes.pts;
          audioPes.dts = parsedPes.dts;
          audioPes.builder.add(parsedPes.payload);
        } else {
          audioPes.builder.add(payload);
        }
      }
    }

    flushVideoPes();
    flushAudioPes();

    final spsBytes = sps;
    final ppsBytes = pps;
    if (videoSamples.isEmpty || spsBytes == null || ppsBytes == null) {
      return null;
    }

    return _buildMp4(
      videoSamples: videoSamples,
      audioSamples: audioSamples,
      sps: spsBytes,
      pps: ppsBytes,
      audioObjType: audioObjType,
      audioFreqIndex: audioFreqIndex,
      audioChannels: audioChannels,
    );
  }

  static int? _parsePat(Uint8List payload, bool pusi) {
    var i = 0;
    if (pusi) {
      if (payload.isEmpty) return null;
      i = 1 + payload[0];
    }
    if (i + 12 > payload.length) return null;
    if (payload[i] != 0x00) return null; // table_id != PAT
    final sectionLen = ((payload[i + 1] & 0x0F) << 8) | payload[i + 2];
    final end = (i + 3 + sectionLen - 4).clamp(0, payload.length);
    for (var j = i + 8; j + 4 <= end; j += 4) {
      final progNum = (payload[j] << 8) | payload[j + 1];
      final pid = ((payload[j + 2] & 0x1F) << 8) | payload[j + 3];
      if (progNum != 0) return pid;
    }
    return null;
  }

  static (int?, int?) _parsePmt(Uint8List payload, bool pusi) {
    var i = 0;
    if (pusi) {
      if (payload.isEmpty) return (null, null);
      i = 1 + payload[0];
    }
    if (i + 12 > payload.length) return (null, null);
    if (payload[i] != 0x02) return (null, null); // table_id != PMT
    final sectionLen = ((payload[i + 1] & 0x0F) << 8) | payload[i + 2];
    final progInfoLen = ((payload[i + 10] & 0x0F) << 8) | payload[i + 11];
    final end = (i + 3 + sectionLen - 4).clamp(0, payload.length);

    int? videoPid;
    int? audioPid;
    var j = i + 12 + progInfoLen;
    while (j + 5 <= end) {
      final streamType = payload[j];
      final elemPid = ((payload[j + 1] & 0x1F) << 8) | payload[j + 2];
      final esInfoLen = ((payload[j + 3] & 0x0F) << 8) | payload[j + 4];
      if (streamType == 0x1B) {
        videoPid ??= elemPid; // H.264
      } else if (streamType == 0x0F || streamType == 0x11) {
        audioPid ??= elemPid; // AAC
      }
      j += 5 + esInfoLen;
    }
    return (videoPid, audioPid);
  }

  static ({int? pts, int? dts, Uint8List payload}) _parsePesHeader(
    Uint8List data,
  ) {
    if (data.length < 9 ||
        data[0] != 0x00 ||
        data[1] != 0x00 ||
        data[2] != 0x01) {
      return (pts: null, dts: null, payload: data);
    }
    final flags = data[7];
    final headerDataLen = data[8];
    final payloadStart = 9 + headerDataLen;
    if (payloadStart > data.length) {
      return (pts: null, dts: null, payload: Uint8List(0));
    }

    int? pts;
    int? dts;
    if ((flags & 0x80) != 0 && data.length >= 14) {
      pts = _readPts(data, 9);
      if ((flags & 0x40) != 0 && data.length >= 19) {
        dts = _readPts(data, 14);
      }
    }
    return (
      pts: pts,
      dts: dts ?? pts,
      payload: Uint8List.sublistView(data, payloadStart),
    );
  }

  static int _readPts(Uint8List data, int pos) {
    return ((data[pos] & 0x0E) << 29) |
        (data[pos + 1] << 22) |
        ((data[pos + 2] & 0xFE) << 14) |
        (data[pos + 3] << 7) |
        ((data[pos + 4] & 0xFE) >> 1);
  }

  static List<Uint8List> _splitAnnexBNalus(Uint8List data) {
    final nalus = <Uint8List>[];
    var i = 0;
    var naluStart = -1;

    while (i + 2 < data.length) {
      if (data[i] == 0x00 && data[i + 1] == 0x00) {
        var startCodeLen = 0;
        if (data[i + 2] == 0x01) {
          startCodeLen = 3;
        } else if (i + 3 < data.length &&
            data[i + 2] == 0x00 &&
            data[i + 3] == 0x01) {
          startCodeLen = 4;
        }
        if (startCodeLen > 0) {
          if (naluStart >= 0 && i > naluStart) {
            nalus.add(Uint8List.sublistView(data, naluStart, i));
          }
          i += startCodeLen;
          naluStart = i;
          continue;
        }
      }
      i++;
    }
    if (naluStart >= 0 && naluStart < data.length) {
      nalus.add(Uint8List.sublistView(data, naluStart));
    }
    return nalus;
  }

  static (int width, int height) _parseSpsDimensions(Uint8List sps) {
    return parseSpsDimensions(sps) ?? (1920, 1080);
  }

  /// Parses display width and height from an H.264 SPS NALU (including NAL header).
  static (int width, int height)? parseSpsDimensions(Uint8List sps) {
    if (sps.length < 4) return null;
    try {
      // Strip NAL header (1 byte) and remove 0x00 0x00 0x03 emulation prevention bytes.
      final rbsp = <int>[];
      var zeroCount = 0;
      for (var i = 1; i < sps.length; i++) {
        final b = sps[i];
        if (zeroCount == 2 && b == 0x03) {
          zeroCount = 0;
          continue;
        }
        zeroCount = b == 0 ? zeroCount + 1 : 0;
        rbsp.add(b);
      }
      if (rbsp.length < 3) return null;

      final reader = _BitReader(rbsp);
      final profileIdc = reader.readBits(8);
      reader.readBits(8); // constraint_set_flags + reserved_zero_2bits
      reader.readBits(8); // level_idc
      reader.readUe(); // seq_parameter_set_id

      var chromaFormatIdc = 1;
      var separateColourPlaneFlag = 0;
      if (const <int>{
        100,
        110,
        122,
        244,
        44,
        83,
        86,
        118,
        128,
        138,
        139,
        134,
        135,
      }.contains(profileIdc)) {
        chromaFormatIdc = reader.readUe();
        if (chromaFormatIdc == 3) {
          separateColourPlaneFlag = reader.readBits(1);
        }
        reader.readUe(); // bit_depth_luma_minus8
        reader.readUe(); // bit_depth_chroma_minus8
        reader.readBits(1); // qpprime_y_zero_transform_bypass_flag
        final seqScalingMatrixPresentFlag = reader.readBits(1);
        if (seqScalingMatrixPresentFlag == 1) {
          final limit = chromaFormatIdc != 3 ? 8 : 12;
          for (var i = 0; i < limit; i++) {
            final present = reader.readBits(1);
            if (present == 1) {
              final size = i < 6 ? 16 : 64;
              var lastScale = 8;
              var nextScale = 8;
              for (var j = 0; j < size; j++) {
                if (nextScale != 0) {
                  final deltaScale = reader.readSe();
                  nextScale = (lastScale + deltaScale + 256) % 256;
                }
                lastScale = nextScale == 0 ? lastScale : nextScale;
              }
            }
          }
        }
      }

      reader.readUe(); // log2_max_frame_num_minus4
      final picOrderCntType = reader.readUe();
      if (picOrderCntType == 0) {
        reader.readUe(); // log2_max_pic_order_cnt_lsb_minus4
      } else if (picOrderCntType == 1) {
        reader.readBits(1); // delta_pic_order_always_zero_flag
        reader.readSe(); // offset_for_non_ref_pic
        reader.readSe(); // offset_for_top_to_bottom_field
        final numRefFrames = reader.readUe();
        for (var i = 0; i < numRefFrames; i++) {
          reader.readSe();
        }
      }

      reader.readUe(); // max_num_ref_frames
      reader.readBits(1); // gaps_in_frame_num_value_allowed_flag
      final picWidthInMbsMinus1 = reader.readUe();
      final picHeightInMapUnitsMinus1 = reader.readUe();
      final frameMbsOnlyFlag = reader.readBits(1);
      if (frameMbsOnlyFlag == 0) {
        reader.readBits(1); // mb_adaptive_frame_field_flag
      }
      reader.readBits(1); // direct_8x8_inference_flag

      var cropLeft = 0;
      var cropRight = 0;
      var cropTop = 0;
      var cropBottom = 0;
      final frameCroppingFlag = reader.readBits(1);
      if (frameCroppingFlag == 1) {
        cropLeft = reader.readUe();
        cropRight = reader.readUe();
        cropTop = reader.readUe();
        cropBottom = reader.readUe();
      }

      final chromaArrayType =
          separateColourPlaneFlag == 0 ? chromaFormatIdc : 0;
      final subWidthC =
          (chromaFormatIdc == 1 || chromaFormatIdc == 2) ? 2 : 1;
      final subHeightC = (chromaFormatIdc == 1) ? 2 : 1;
      final cropUnitX = chromaArrayType == 0 ? 1 : subWidthC;
      final cropUnitY =
          (chromaArrayType == 0 ? 1 : subHeightC) * (2 - frameMbsOnlyFlag);

      final width =
          (picWidthInMbsMinus1 + 1) * 16 - cropUnitX * (cropLeft + cropRight);
      final height = (2 - frameMbsOnlyFlag) *
              (picHeightInMapUnitsMinus1 + 1) *
              16 -
          cropUnitY * (cropTop + cropBottom);

      if (width > 0 && height > 0) {
        return (width, height);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _buildMp4({
    required List<_MediaSample> videoSamples,
    required List<_MediaSample> audioSamples,
    required Uint8List sps,
    required Uint8List pps,
    required int audioObjType,
    required int audioFreqIndex,
    required int audioChannels,
  }) {
    final ftyp = _box('ftyp', <int>[
      ..._ascii('isom'),
      0x00, 0x00, 0x02, 0x00,
      ..._ascii('isom'),
      ..._ascii('iso2'),
      ..._ascii('avc1'),
      ..._ascii('mp41'),
    ]);

    // Build mdat payload and record chunk offsets (relative to mdat payload start)
    final mdatBody = BytesBuilder(copy: false);
    final videoOffsets = <int>[];
    for (final s in videoSamples) {
      videoOffsets.add(mdatBody.length);
      mdatBody.add(s.data);
    }
    final audioOffsets = <int>[];
    for (final s in audioSamples) {
      audioOffsets.add(mdatBody.length);
      mdatBody.add(s.data);
    }

    final mdatData = mdatBody.takeBytes();
    final mdatHeaderSize = 8;
    final mdatBaseOffset = ftyp.length + mdatHeaderSize;

    final videoDuration = _computeTrackDuration(videoSamples, 3000);
    final audioSampleRate = audioFreqIndex < _aacSampleRates.length
        ? _aacSampleRates[audioFreqIndex]
        : 44100;
    final audioDuration = audioSamples.length * 1024;
    final movieDuration = videoDuration;

    final (width, height) = _parseSpsDimensions(sps);

    final mvhd = _buildMvhd(timescale: 90000, duration: movieDuration);
    final videoTrak = _buildVideoTrak(
      trackId: 1,
      timescale: 90000,
      duration: videoDuration,
      width: width,
      height: height,
      sps: sps,
      pps: pps,
      samples: videoSamples,
      baseOffset: mdatBaseOffset,
      relativeOffsets: videoOffsets,
    );

    final moovChildren = <Uint8List>[mvhd, videoTrak];
    if (audioSamples.isNotEmpty) {
      moovChildren.add(
        _buildAudioTrak(
          trackId: 2,
          timescale: audioSampleRate,
          duration: audioDuration,
          movieTimescale: 90000,
          movieDuration: movieDuration,
          samples: audioSamples,
          baseOffset: mdatBaseOffset,
          relativeOffsets: audioOffsets,
          audioObjType: audioObjType,
          audioFreqIndex: audioFreqIndex,
          audioChannels: audioChannels,
        ),
      );
    }

    final moov = _box('moov', _concat(moovChildren));
    final mdat = _box('mdat', mdatData);

    return _concat(<Uint8List>[ftyp, mdat, moov]);
  }

  static int _computeTrackDuration(
    List<_MediaSample> samples,
    int defaultDelta,
  ) {
    if (samples.length <= 1) return defaultDelta;
    var total = 0;
    for (var i = 0; i < samples.length - 1; i++) {
      final delta = samples[i + 1].dts - samples[i].dts;
      total += delta > 0 ? delta : defaultDelta;
    }
    return total + defaultDelta;
  }

  static Uint8List _buildMvhd({required int timescale, required int duration}) {
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]); // version + flags
    b.add(_u32(0)); // creation_time
    b.add(_u32(0)); // modification_time
    b.add(_u32(timescale));
    b.add(_u32(duration));
    b.add(_u32(0x00010000)); // rate 1.0
    b.add(<int>[0x01, 0x00]); // volume 1.0
    b.add(Uint8List(10)); // reserved
    b.add(_unityMatrix());
    b.add(Uint8List(24)); // pre_defined
    b.add(_u32(3)); // next_track_id
    return _box('mvhd', b.takeBytes());
  }

  static Uint8List _buildVideoTrak({
    required int trackId,
    required int timescale,
    required int duration,
    required int width,
    required int height,
    required Uint8List sps,
    required Uint8List pps,
    required List<_MediaSample> samples,
    required int baseOffset,
    required List<int> relativeOffsets,
  }) {
    final tkhd = BytesBuilder();
    tkhd.add(<int>[0, 0, 0, 3]); // flags: enabled + in_movie
    tkhd.add(_u32(0));
    tkhd.add(_u32(0));
    tkhd.add(_u32(trackId));
    tkhd.add(_u32(0));
    tkhd.add(_u32(duration));
    tkhd.add(Uint8List(8));
    tkhd.add(<int>[0, 0, 0, 0, 0, 0, 0, 0]);
    tkhd.add(_unityMatrix());
    tkhd.add(_u32(width << 16));
    tkhd.add(_u32(height << 16));

    final mdhd = _buildMdhd(timescale: timescale, duration: duration);
    final hdlr = _buildHdlr('vide', 'VideoHandler');
    final vmhd = _box('vmhd', <int>[0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]);
    final dinf = _buildDinf();

    // avcC
    final avcc = BytesBuilder();
    avcc.add(<int>[
      1,
      sps.length > 1 ? sps[1] : 0x64,
      sps.length > 2 ? sps[2] : 0x00,
      sps.length > 3 ? sps[3] : 0x1F,
      0xFF, // lengthSizeMinusOne = 3 (4 bytes)
      0xE1, // 1 SPS
    ]);
    avcc.add(_u16(sps.length));
    avcc.add(sps);
    avcc.add(<int>[1]); // 1 PPS
    avcc.add(_u16(pps.length));
    avcc.add(pps);

    final avc1 = BytesBuilder();
    avc1.add(Uint8List(6));
    avc1.add(_u16(1)); // data_reference_index
    avc1.add(Uint8List(16));
    avc1.add(_u16(width));
    avc1.add(_u16(height));
    avc1.add(_u32(0x00480000));
    avc1.add(_u32(0x00480000));
    avc1.add(_u32(0));
    avc1.add(_u16(1));
    avc1.add(Uint8List(32));
    avc1.add(_u16(0x0018));
    avc1.add(_u16(0xFFFF));
    avc1.add(_box('avcC', avcc.takeBytes()));

    final stsd = _box(
      'stsd',
      _concat(<Uint8List>[
        Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 1]),
        _box('avc1', avc1.takeBytes()),
      ]),
    );

    final stts = _buildStts(samples, 3000);
    final stss = _buildStss(samples);
    final stsc = _buildStscOnePerChunk();
    final stsz = _buildStsz(samples);
    final co64 = _buildCo64(baseOffset, relativeOffsets);

    final stbl = _box(
      'stbl',
      _concat(<Uint8List>[stsd, stts, stss, stsc, stsz, co64]),
    );
    final minf = _box('minf', _concat(<Uint8List>[vmhd, dinf, stbl]));
    final mdia = _box('mdia', _concat(<Uint8List>[mdhd, hdlr, minf]));

    return _box(
      'trak',
      _concat(<Uint8List>[_box('tkhd', tkhd.takeBytes()), mdia]),
    );
  }

  static Uint8List _buildAudioTrak({
    required int trackId,
    required int timescale,
    required int duration,
    required int movieTimescale,
    required int movieDuration,
    required List<_MediaSample> samples,
    required int baseOffset,
    required List<int> relativeOffsets,
    required int audioObjType,
    required int audioFreqIndex,
    required int audioChannels,
  }) {
    final tkhd = BytesBuilder();
    tkhd.add(<int>[0, 0, 0, 3]);
    tkhd.add(_u32(0));
    tkhd.add(_u32(0));
    tkhd.add(_u32(trackId));
    tkhd.add(_u32(0));
    tkhd.add(_u32(movieDuration));
    tkhd.add(Uint8List(8));
    tkhd.add(<int>[0, 0, 0, 0, 0x01, 0x00, 0, 0]);
    tkhd.add(_unityMatrix());
    tkhd.add(_u32(0));
    tkhd.add(_u32(0));

    final mdhd = _buildMdhd(timescale: timescale, duration: duration);
    final hdlr = _buildHdlr('soun', 'SoundHandler');
    final smhd = _box('smhd', <int>[0, 0, 0, 0, 0, 0, 0, 0]);
    final dinf = _buildDinf();

    final ascByte1 = ((audioObjType & 0x1F) << 3) | ((audioFreqIndex >> 1) & 0x07);
    final ascByte2 = ((audioFreqIndex & 0x01) << 7) | ((audioChannels & 0x0F) << 3);

    final esds = _box('esds', <int>[
      0, 0, 0, 0, // version + flags
      0x03, 25, // ES_DescrTag
      0x00, 0x02, 0x00, // ES_ID=2, flags=0
      0x04, 17, // DecoderConfigDescrTag
      0x40, 0x15, // MPEG-4 Audio, streamType=5
      0x00, 0x00, 0x00,
      0x00, 0x01, 0xF4, 0x00, // maxBitrate
      0x00, 0x01, 0xF4, 0x00, // avgBitrate
      0x05, 2, ascByte1, ascByte2, // AudioSpecificConfig
      0x06, 1, 0x02, // SLConfigDescriptor
    ]);

    final mp4a = BytesBuilder();
    mp4a.add(Uint8List(6));
    mp4a.add(_u16(1)); // data_reference_index
    mp4a.add(Uint8List(8));
    mp4a.add(_u16(audioChannels));
    mp4a.add(_u16(16)); // sampleSize
    mp4a.add(Uint8List(4));
    mp4a.add(_u32(timescale << 16));
    mp4a.add(esds);

    final stsd = _box(
      'stsd',
      _concat(<Uint8List>[
        Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 1]),
        _box('mp4a', mp4a.takeBytes()),
      ]),
    );

    final stts = _box('stts', <int>[
      0, 0, 0, 0,
      ..._u32(1),
      ..._u32(samples.length),
      ..._u32(1024),
    ]);
    final stsc = _buildStscOnePerChunk();
    final stsz = _buildStsz(samples);
    final co64 = _buildCo64(baseOffset, relativeOffsets);

    final stbl = _box(
      'stbl',
      _concat(<Uint8List>[stsd, stts, stsc, stsz, co64]),
    );
    final minf = _box('minf', _concat(<Uint8List>[smhd, dinf, stbl]));
    final mdia = _box('mdia', _concat(<Uint8List>[mdhd, hdlr, minf]));

    return _box(
      'trak',
      _concat(<Uint8List>[_box('tkhd', tkhd.takeBytes()), mdia]),
    );
  }

  static Uint8List _buildMdhd({required int timescale, required int duration}) {
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(0));
    b.add(_u32(0));
    b.add(_u32(timescale));
    b.add(_u32(duration));
    b.add(<int>[0x55, 0xC4, 0, 0]); // 'und'
    return _box('mdhd', b.takeBytes());
  }

  static Uint8List _buildHdlr(String type, String name) {
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(0));
    b.add(_ascii(type));
    b.add(Uint8List(12));
    b.add(_ascii(name));
    b.add(<int>[0]);
    return _box('hdlr', b.takeBytes());
  }

  static Uint8List _buildDinf() {
    final url = _box('url ', <int>[0, 0, 0, 1]);
    final dref = _box(
      'dref',
      _concat(<Uint8List>[
        Uint8List.fromList(<int>[0, 0, 0, 0, 0, 0, 0, 1]),
        url,
      ]),
    );
    return _box('dinf', dref);
  }

  static Uint8List _buildStts(List<_MediaSample> samples, int defaultDelta) {
    final entries = <(int count, int delta)>[];
    for (var i = 0; i < samples.length; i++) {
      final delta = (i + 1 < samples.length)
          ? (samples[i + 1].dts - samples[i].dts)
          : defaultDelta;
      final validDelta = delta > 0 ? delta : defaultDelta;
      if (entries.isNotEmpty && entries.last.$2 == validDelta) {
        entries[entries.length - 1] = (entries.last.$1 + 1, validDelta);
      } else {
        entries.add((1, validDelta));
      }
    }
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(entries.length));
    for (final e in entries) {
      b.add(_u32(e.$1));
      b.add(_u32(e.$2));
    }
    return _box('stts', b.takeBytes());
  }

  static Uint8List _buildStss(List<_MediaSample> samples) {
    final keyIndices = <int>[];
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].isKeyFrame) keyIndices.add(i + 1);
    }
    if (keyIndices.isEmpty) keyIndices.add(1);
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(keyIndices.length));
    for (final idx in keyIndices) {
      b.add(_u32(idx));
    }
    return _box('stss', b.takeBytes());
  }

  static Uint8List _buildStscOnePerChunk() {
    return _box('stsc', <int>[
      0, 0, 0, 0,
      ..._u32(1),
      ..._u32(1),
      ..._u32(1),
      ..._u32(1),
    ]);
  }

  static Uint8List _buildStsz(List<_MediaSample> samples) {
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(0));
    b.add(_u32(samples.length));
    for (final s in samples) {
      b.add(_u32(s.data.length));
    }
    return _box('stsz', b.takeBytes());
  }

  static Uint8List _buildCo64(int baseOffset, List<int> relativeOffsets) {
    final b = BytesBuilder();
    b.add(<int>[0, 0, 0, 0]);
    b.add(_u32(relativeOffsets.length));
    for (final rel in relativeOffsets) {
      b.add(_u64(baseOffset + rel));
    }
    return _box('co64', b.takeBytes());
  }

  static Uint8List _box(String type, List<int> payload) {
    final size = 8 + payload.length;
    final b = BytesBuilder(copy: false);
    b.add(_u32(size));
    b.add(_ascii(type));
    b.add(payload);
    return b.takeBytes();
  }

  static Uint8List _concat(List<Uint8List> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) {
      b.add(p);
    }
    return b.takeBytes();
  }

  static List<int> _ascii(String s) => s.codeUnits;

  static List<int> _u16(int v) => <int>[(v >> 8) & 0xFF, v & 0xFF];

  static List<int> _u32(int v) => <int>[
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  static List<int> _u64(int v) => <int>[
        (v >> 56) & 0xFF,
        (v >> 48) & 0xFF,
        (v >> 40) & 0xFF,
        (v >> 32) & 0xFF,
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  static List<int> _unityMatrix() => <int>[
        ..._u32(0x00010000),
        ..._u32(0),
        ..._u32(0),
        ..._u32(0),
        ..._u32(0x00010000),
        ..._u32(0),
        ..._u32(0),
        ..._u32(0),
        ..._u32(0x40000000),
      ];
}

class _BitReader {
  _BitReader(this._bytes);

  final List<int> _bytes;
  int _byteOffset = 0;
  int _bitOffset = 0;

  int readBits(int count) {
    var result = 0;
    for (var i = 0; i < count; i++) {
      if (_byteOffset >= _bytes.length) {
        throw const FormatException('Unexpected end of SPS RBSP');
      }
      final bit = (_bytes[_byteOffset] >> (7 - _bitOffset)) & 0x01;
      result = (result << 1) | bit;
      _bitOffset++;
      if (_bitOffset == 8) {
        _bitOffset = 0;
        _byteOffset++;
      }
    }
    return result;
  }

  int readUe() {
    var leadingZeros = 0;
    while (readBits(1) == 0) {
      leadingZeros++;
      if (leadingZeros > 31) {
        throw const FormatException('Exp-Golomb overflow');
      }
    }
    if (leadingZeros == 0) return 0;
    final suffix = readBits(leadingZeros);
    return ((1 << leadingZeros) - 1) + suffix;
  }

  int readSe() {
    final ue = readUe();
    if (ue == 0) return 0;
    final sign = (ue & 1) == 1 ? 1 : -1;
    return sign * ((ue + 1) >> 1);
  }
}
