// Server manzili. Yig'ishda o'zgartirish mumkin:
//   flutter run --dart-define=API_URL=https://sizning-server.uz
// Android emulyatorida kompyuterdagi serverga 10.0.2.2 orqali ulanadi.
const String apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:3000',
);
