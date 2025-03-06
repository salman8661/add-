import 'package:flutter/material.dart';
import '../services/message_service.dart';
import '../models/message.dart';

class ChatScreen extends StatefulWidget {
  final String token;

  ChatScreen({required this.token});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  List<Message> _messages = [];

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  void _fetchMessages() async {
    final messages = await MessageService.getMessages(widget.token);
    setState(() {
      _messages = messages;
    });
  }

  void _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    await MessageService.sendMessage(widget.token, _messageController.text);
    _messageController.clear();
    _fetchMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_messages[index].content),
                  subtitle: Text(
                    '${_messages[index].sender.username} - ${_messages[index].timestamp.toLocal()}',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(labelText: 'Send a message...'),
                  ),
                ),
                IconButton(icon: Icon(Icons.send), onPressed: _sendMessage),
              ],
            ),
          )
        ],
      ),
    );
  }
}
