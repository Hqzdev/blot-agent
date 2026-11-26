import { createDocumentHandler } from '@/lib/artifacts/server';
import {
  GigaChatImageGenerator,
  GigaChatImageGeneratorFactory,
} from '@teya/service-ai-gateway';

let imageGenerator: GigaChatImageGenerator | undefined;

function getImageGenerator(): GigaChatImageGenerator {
  imageGenerator ??= new GigaChatImageGeneratorFactory().create(process.env);
  return imageGenerator;
}

export const imageDocumentHandler = createDocumentHandler<'image'>({
  kind: 'image',
  onCreateDocument: async ({ title, dataStream }) => {
    const image = await getImageGenerator().generate(title);

    dataStream.writeData({
      type: 'image-delta',
      content: image.base64,
    });

    return image.base64;
  },
  onUpdateDocument: async ({ description, dataStream }) => {
    const image = await getImageGenerator().generate(description);

    dataStream.writeData({
      type: 'image-delta',
      content: image.base64,
    });

    return image.base64;
  },
});
