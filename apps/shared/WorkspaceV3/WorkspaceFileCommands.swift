import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceFileCommands: WorkspaceObservationService {
    func importWorkspaceFile(_ source: URL) async throws -> UUID
    func readWorkspaceFile(_ id: UUID, startPage: Int, pageCount: Int) async throws -> WorkspaceExtractedText
}
@MainActor
protocol WorkspaceFileProviding { var workspaceFiles: (any WorkspaceFileCommands)? { get } }

enum WorkspaceFileFailure {
    static func text(_ error: Error, russian: Bool) -> String {
        switch error {
        case WorkspaceFileError.unsupportedType:
            russian ? "Поддерживаются текстовые файлы, PDF и изображения PNG, JPEG, HEIC, TIFF и WebP." : "Supported formats: text, PDF, PNG, JPEG, HEIC, TIFF and WebP."
        case WorkspaceFileError.tooLarge:
            russian ? "Файл превышает лимит 32 МБ." : "The file exceeds the 32 MB limit."
        case WorkspaceFileError.noRecognizableText:
            russian ? "На выбранных страницах не найден текст. Можно открыть оригинал файла." : "No text was found on these pages. You can open the original file."
        case WorkspaceFileError.unreadableImage:
            russian ? "Изображение повреждено или имеет слишком большое разрешение." : "The image is damaged or its resolution is too large."
        case WorkspaceFileError.unreadablePDF:
            russian ? "PDF повреждён, защищён паролем или содержит больше 1000 страниц." : "The PDF is damaged, password protected or exceeds 1,000 pages."
        case WorkspaceFileError.invalidText:
            russian ? "Текстовый файл должен быть в кодировке UTF-8." : "The text file must use UTF-8 encoding."
        case WorkspaceFileError.integrityMismatch:
            russian ? "Проверка целостности файла не пройдена. Импортируйте оригинал заново." : "File integrity verification failed. Import the original again."
        case WorkspaceFileError.recognitionFailed:
            russian ? "Не удалось распознать текст. Попробуйте более чёткое изображение." : "Text recognition failed. Try a clearer image."
        case WorkspaceStorageError.invalidParameters:
            russian ? "Проверьте номер страницы и параметры файла." : "Check the page number and file parameters."
        default:
            russian ? "Файл недоступен на этом устройстве. Дождитесь синхронизации или импортируйте оригинал." : "The file is unavailable on this device. Wait for sync or import the original."
        }
    }
}
