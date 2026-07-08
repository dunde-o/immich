import { createZodDto } from 'nestjs-zod';
import { Stack } from 'src/database';
import { AssetResponseSchema, mapAsset } from 'src/dtos/asset-response.dto';
import { AuthDto } from 'src/dtos/auth.dto';
import z from 'zod';

const StackSearchSchema = z
  .object({
    primaryAssetId: z.uuidv4().optional().describe('Filter by primary asset ID'),
  })
  .meta({ id: 'StackSearchDto' });

const StackCreateSchema = z
  .object({
    assetIds: z.array(z.uuidv4()).min(2).describe('Asset IDs (first becomes primary, min 2)'),
  })
  .meta({ id: 'StackCreateDto' });

const StackUpdateSchema = z
  .object({
    primaryAssetId: z.uuidv4().optional().describe('Primary asset ID'),
  })
  .meta({ id: 'StackUpdateDto' });

const StackResponseSchema = z
  .object({
    id: z.uuidv4().describe('Stack ID'),
    primaryAssetId: z.uuidv4().describe('Primary asset ID'),
    assets: z.array(AssetResponseSchema),
  })
  .describe('Stack response')
  .meta({ id: 'StackResponseDto' });

export class StackSearchDto extends createZodDto(StackSearchSchema) {}
export class StackCreateDto extends createZodDto(StackCreateSchema) {}
export class StackUpdateDto extends createZodDto(StackUpdateSchema) {}
export class StackResponseDto extends createZodDto(StackResponseSchema) {}

export const mapStack = (stack: Stack, { auth }: { auth?: AuthDto }) => {
  return {
    id: stack.id,
    primaryAssetId: stack.primaryAssetId,
    // 대표이미지를 맨 앞으로 당기지 않고 리포지토리의 시간순(localDateTime) 정렬을 유지한다.
    // 대표 표시는 프론트엔드 스택 스트립의 별(star) 뱃지로 처리한다.
    assets: stack.assets.map((asset) => mapAsset(asset, { auth })),
  };
};
