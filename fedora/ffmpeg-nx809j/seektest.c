// Decode FILE with DECODER, seek back to the start after SEEK_AT frames (as
// a player does), decode to the end, then (if LOOP) seek again after EOF and
// decode once more. Prints one md5 per frame so runs can be compared.
// Usage: seektest FILE DECODER SEEK_AT LOOP
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/md5.h>
#include <libavutil/imgutils.h>
#include <stdio.h>
#include <stdlib.h>

static AVFormatContext *fmt;
static AVCodecContext *dec;
static int vs, nframes;

static void dump(AVFrame *f)
{
	uint8_t d[16], *buf;
	int size = av_image_get_buffer_size(f->format, f->width, f->height, 1);

	buf = malloc(size);
	av_image_copy_to_buffer(buf, size, (const uint8_t * const *)f->data,
				f->linesize, f->format, f->width, f->height, 1);
	av_md5_sum(d, buf, size);
	free(buf);
	printf("%d ", nframes++);
	for (int i = 0; i < 16; i++)
		printf("%02x", d[i]);
	printf("\n");
}

/* Feed packets and print frames until LIMIT frames this pass or EOF. */
static int pass(int limit)
{
	AVPacket *pkt = av_packet_alloc();
	AVFrame *f = av_frame_alloc();
	int got = 0, eof = 0, ret;

	while (limit < 0 || got < limit) {
		if (!eof) {
			ret = av_read_frame(fmt, pkt);
			if (ret < 0) {
				avcodec_send_packet(dec, NULL);
				eof = 1;
			} else {
				if (pkt->stream_index == vs)
					avcodec_send_packet(dec, pkt);
				av_packet_unref(pkt);
			}
		}
		while ((ret = avcodec_receive_frame(dec, f)) >= 0) {
			dump(f);
			got++;
		}
		if (ret == AVERROR_EOF)
			break;
	}
	av_frame_free(&f);
	av_packet_free(&pkt);
	return got;
}

int main(int argc, char **argv)
{
	const AVCodec *c;
	int seek_at = atoi(argv[3]), loop = atoi(argv[4]);

	if (avformat_open_input(&fmt, argv[1], NULL, NULL) < 0 ||
	    avformat_find_stream_info(fmt, NULL) < 0)
		return 1;
	vs = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
	c = avcodec_find_decoder_by_name(argv[2]);
	dec = avcodec_alloc_context3(c);
	avcodec_parameters_to_context(dec, fmt->streams[vs]->codecpar);
	if (avcodec_open2(dec, c, NULL) < 0)
		return 1;

	fprintf(stderr, "pass 1: %d\n", pass(seek_at));
	av_seek_frame(fmt, vs, 0, AVSEEK_FLAG_BACKWARD);
	avcodec_flush_buffers(dec);
	fprintf(stderr, "pass 2 (mid-stream seek): %d\n", pass(-1));
	if (loop) {
		av_seek_frame(fmt, vs, 0, AVSEEK_FLAG_BACKWARD);
		avcodec_flush_buffers(dec);
		fprintf(stderr, "pass 3 (seek after EOF): %d\n", pass(-1));
	}
	avcodec_free_context(&dec);
	avformat_close_input(&fmt);
	return 0;
}
