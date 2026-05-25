import type { AssetResponseDto } from '@immich/sdk';
import { canCopyImageToClipboard, getAssetFilename, getFilenameExtension, sortStackAssetsByTime } from './asset-utils';

describe('get file extension from filename', () => {
  it('returns the extension without including the dot', () => {
    expect(getFilenameExtension('filename.txt')).toEqual('txt');
  });

  it('takes the last file extension and ignores the rest', () => {
    expect(getFilenameExtension('filename.txt.pdf')).toEqual('pdf');
    expect(getFilenameExtension('filename.txt.pdf.jpg')).toEqual('jpg');
  });

  it('returns an empty string when no file extension is found', () => {
    expect(getFilenameExtension('filename')).toEqual('');
    expect(getFilenameExtension('filename.')).toEqual('');
    expect(getFilenameExtension('filename..')).toEqual('');
    expect(getFilenameExtension('.filename')).toEqual('');
  });

  it('returns the extension from a filepath', () => {
    expect(getFilenameExtension('/folder/file.txt')).toEqual('txt');
    expect(getFilenameExtension('./folder/file.txt')).toEqual('txt');
    expect(getFilenameExtension('~/folder/file.txt')).toEqual('txt');
    expect(getFilenameExtension('./folder/.file.txt')).toEqual('txt');
    expect(getFilenameExtension('/folder.with.dots/file.txt')).toEqual('txt');
  });
});

describe('get asset filename', () => {
  it('returns the filename including file extension', () => {
    for (const { asset, result } of [
      {
        asset: {
          originalFileName: 'filename',
          originalPath: '/data/library/test/2016/2016-08-30/filename.jpg',
        },
        result: 'filename.jpg',
      },
      {
        asset: {
          originalFileName: 'new-filename',
          originalPath: '/data/library/89d14e47-a40d-4cae-a347-a914cdef1f22/2016/2016-08-30/filename.jpg',
        },
        result: 'new-filename.jpg',
      },
      {
        asset: {
          originalFileName: 'new-filename.txt',
          originalPath: '/data/library/test/2016/2016-08-30/filename.txt.jpg',
        },
        result: 'new-filename.txt.jpg',
      },
    ]) {
      expect(getAssetFilename(asset as AssetResponseDto)).toEqual(result);
    }
  });
});

describe('copy image to clipboard', () => {
  // This test is dubious, as it totally on the environment where the test is run which is mocked.
  it('should allow copy image to clipboard', () => {
    expect(canCopyImageToClipboard()).toEqual(true);
  });
});

describe('sort stack assets by time', () => {
  it('sorts assets by local date time before stacking', () => {
    const sorted = sortStackAssetsByTime([
      { id: 'c', localDateTime: '2026-01-01T10:00:02.000Z' },
      { id: 'a', localDateTime: '2026-01-01T10:00:00.000Z' },
      { id: 'b', localDateTime: '2026-01-01T10:00:01.000Z' },
    ]);

    expect(sorted.map((asset) => asset.id)).toEqual(['a', 'b', 'c']);
  });

  it('uses id as a stable tie breaker for assets with the same time', () => {
    const sorted = sortStackAssetsByTime([
      { id: 'b', localDateTime: '2026-01-01T10:00:00.000Z' },
      { id: 'a', localDateTime: '2026-01-01T10:00:00.000Z' },
    ]);

    expect(sorted.map((asset) => asset.id)).toEqual(['a', 'b']);
  });
});
