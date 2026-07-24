import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  // Método para capturar foto e extrair a Placa
  Future<String?> lerPlacaDaCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image == null) return null; // Usuário cancelou a foto

    final inputImage = InputImage.fromFilePath(image.path);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Expressão regular para procurar padrão de placa (Ex: ABC1D23 ou ABC-1234)
    final RegExp regexPlaca = RegExp(r'[A-Z]{3}[0-9][A-Z0-9][0-9]{2}');

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        String textoLimpo = line.text.replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (regexPlaca.hasMatch(textoLimpo)) {
          return textoLimpo;
        }
      }
    }

    // Retorna o primeiro texto encontrado caso o padrão exato não seja identificado de primeira
    return recognizedText.text.isNotEmpty ? recognizedText.text.split('\n').first : null;
  }

  // Método para capturar foto e extrair a Quilometragem (KM) do Painel
  Future<String?> lerKmDoPainel() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image == null) return null;

    final inputImage = InputImage.fromFilePath(image.path);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

    // Procura por números que representem o KM (ex: números de 2 a 6 dígitos)
    final RegExp regexKm = RegExp(r'[0-9]{2,6}');

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        if (regexKm.hasMatch(line.text)) {
          return line.text.trim();
        }
      }
    }

    return recognizedText.text.isNotEmpty ? recognizedText.text.trim() : null;
  }

  void dispose() {
    _textRecognizer.close();
  }
}