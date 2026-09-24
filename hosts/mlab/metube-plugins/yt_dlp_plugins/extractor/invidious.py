from yt_dlp.extractor.common import InfoExtractor


class YoutubeInvidiousRedirectIE(InfoExtractor):
    INVIDIOUS_URLS = (r'(?:www\.)?yt\.marcel\.cool',)
    _VALID_URL = r'https?://(?P<invidious_base>{})'.format('|'.join(INVIDIOUS_URLS))

    def _real_extract(self, url):
        invidious_base = self._match_valid_url(url).group('invidious_base')
        return self.url_result(url.replace(invidious_base, 'www.youtube.com'))
