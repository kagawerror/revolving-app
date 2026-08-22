import 'package:equatable/equatable.dart';

class Company extends Equatable {
  final String id;
  final String name;
  const Company({required this.id, required this.name});

  factory Company.fromMap(String id, Map<String, dynamic> m) =>
      Company(id: id, name: (m['name'] ?? '') as String);

  Map<String, dynamic> toMap() => {'name': name};

  @override
  List<Object?> get props => [id, name];
}
