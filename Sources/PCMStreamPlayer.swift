import AudioToolbox
import Foundation

struct PCMBufferFIFO {
    private var data = Data()
    private var offset = 0
    var count: Int { data.count - offset }
    mutating func append(_ bytes: Data) { data.append(bytes) }
    mutating func take(maximum: Int) -> Data {
        let length = min(count, maximum) / 2 * 2 // Never split a signed 16-bit sample.
        let start = data.startIndex + offset
        let result = data.subdata(in: start..<(start + length))
        offset += length
        if offset == data.count { data.removeAll(keepingCapacity: true); offset = 0 }
        else if offset > 65536 { data.removeFirst(offset); offset = 0 }
        return result
    }
}

/// Main-run-loop owned AudioQueue. Four reusable buffers, 400 ms initial
/// prebuffer, bounded FIFO, and exactly one terminal callback per utterance.
final class PCMStreamPlayer {
    var onStart: (() -> Void)?
    var onFinish: ((Result<Void, Error>) -> Void)?
    private var queue: AudioQueueRef?
    private var available: [AudioQueueBufferRef] = []
    private var fifo = PCMBufferFIFO()
    private var inFlight = 0
    private var queuedBytes = 0
    private var ended = false
    private var started = false
    private var closed = false
    private var prefix = Data()
    private var checkedPrefix = false
    private let bufferSize: Int
    private(set) var acceptedBytes = 0
    private(set) var consumedBytes = 0
    private(set) var underruns = 0
    let sampleRate: Int

    init(sampleRate: Int, outputDeviceUID: String? = nil) throws {
        self.sampleRate = sampleRate
        bufferSize = sampleRate / 5 // 100 ms, mono PCM16.
        var format = AudioStreamBasicDescription(mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        let status = AudioQueueNewOutput(&format, { context, queue, buffer in
            guard let context = context else { return }
            let owner = Unmanaged<PCMStreamPlayer>.fromOpaque(context).takeUnretainedValue()
            owner.returned(buffer)
        }, Unmanaged.passUnretained(self).toOpaque(), CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue, 0, &queue)
        guard status == noErr, let queue = queue else { throw Self.error(status) }
        if let uid = outputDeviceUID {
            let value = uid as CFString
            var device = Unmanaged.passUnretained(value)
            let result = withExtendedLifetime(value) {
                AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &device, UInt32(MemoryLayout<Unmanaged<CFString>>.size))
            }
            guard result == noErr else { stop(); throw BuddySettingsError.invalid("所选输出设备不可用，请重新选择或跟随系统。") }
        }
        for _ in 0..<4 {
            var buffer: AudioQueueBufferRef?
            let result = AudioQueueAllocateBuffer(queue, UInt32(bufferSize), &buffer)
            guard result == noErr, let buffer = buffer else { stop(); throw Self.error(result) }
            available.append(buffer)
        }
    }
    func append(_ data: Data) throws {
        guard !closed, !ended else { return }
        acceptedBytes += data.count
        guard acceptedBytes <= 16_000_000, fifo.count + data.count <= 8_000_000 else { throw BuddySettingsError.invalid("语音流超过播放缓冲上限。") }
        if !checkedPrefix {
            prefix.append(data)
            guard prefix.count >= 4 else { return }
            guard !["RIFF", "OggS", "ID3"].contains(where: { prefix.starts(with: Data($0.utf8)) }) else { throw BuddySettingsError.invalid("服务返回压缩音频或 WAV，请改为原始 PCM16 LE。") }
            fifo.append(prefix); prefix.removeAll(); checkedPrefix = true
        } else { fifo.append(data) }
        try fill()
    }
    func finish() throws {
        guard !closed else { return }
        ended = true
        if !prefix.isEmpty { fifo.append(prefix); prefix.removeAll() }
        guard acceptedBytes > 0, acceptedBytes % 2 == 0 else { throw BuddySettingsError.invalid("语音流为空，或 PCM 样本不完整。") }
        try fill()
    }
    func stop() {
        guard !closed else { return }
        closed = true
        onStart = nil; onFinish = nil
        if let queue = queue { AudioQueueStop(queue, true); AudioQueueDispose(queue, true) }
        queue = nil; available.removeAll(); fifo = PCMBufferFIFO()
    }
    private func fill() throws {
        guard !closed, let queue = queue else { return }
        while !available.isEmpty, fifo.count >= bufferSize || (ended && fifo.count >= 2) {
            let buffer = available.removeLast()
            let data = fifo.take(maximum: bufferSize)
            data.withUnsafeBytes { bytes in buffer.pointee.mAudioData.copyMemory(from: bytes.baseAddress!, byteCount: data.count) }
            buffer.pointee.mAudioDataByteSize = UInt32(data.count)
            let status = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            guard status == noErr else { throw Self.error(status) }
            inFlight += 1; queuedBytes += data.count
        }
        if !started, inFlight > 0, queuedBytes >= bufferSize * 4 || ended {
            let status = AudioQueueStart(queue, nil)
            guard status == noErr else { throw Self.error(status) }
            started = true; onStart?()
        }
        if ended, inFlight == 0, fifo.count == 0 {
            let callback = onFinish; stop(); callback?(.success(()))
        }
    }
    private func returned(_ buffer: AudioQueueBufferRef) {
        guard !closed else { return }
        consumedBytes += Int(buffer.pointee.mAudioDataByteSize)
        inFlight -= 1; available.append(buffer)
        if started && !ended && inFlight == 0 && fifo.count < 2 { underruns += 1 }
        do { try fill() }
        catch { let callback = onFinish; stop(); callback?(.failure(error)) }
    }
    private static func error(_ status: OSStatus) -> Error { BuddySettingsError.invalid("音频设备返回错误码 \(status)。") }
    deinit { stop() }
}
