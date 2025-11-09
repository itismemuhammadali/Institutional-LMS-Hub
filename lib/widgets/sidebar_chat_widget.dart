import 'package:flutter/material.dart';
import '../services/api_service.dart'; // Import the new API service

/// A floating, draggable chat widget that can be moved anywhere on the screen.
/// 
/// Usage:
/// ```dart
/// Scaffold(
///   body: Stack(
///     children: [
///       // Your main content here
///       YourMainWidget(),
///       // Add the floating chat widget
///       FloatingChatWidget(),
///     ],
///   ),
/// )
/// ```

class FloatingChatWidget extends StatefulWidget {
  const FloatingChatWidget({super.key});

  @override
  State<FloatingChatWidget> createState() => _FloatingChatWidgetState();
}

class _FloatingChatWidgetState extends State<FloatingChatWidget> {
  bool _isChatOpen = false;
  Offset _position = const Offset(20, 100); // Initial position

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Draggable floating button
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: Draggable(
            feedback: _buildFloatingButton(isDragging: true),
            childWhenDragging: Container(), // Hide original when dragging
            onDragEnd: (details) {
              setState(() {
                // Keep button within screen bounds
                final screenSize = MediaQuery.of(context).size;
                _position = Offset(
                  details.offset.dx.clamp(0, screenSize.width - 60),
                  details.offset.dy.clamp(0, screenSize.height - 60),
                );
              });
            },
            child: _buildFloatingButton(),
          ),
        ),
        // Chat interface overlay
        if (_isChatOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _isChatOpen = false),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: GestureDetector(
                    onTap: () {}, // Prevent closing when tapping on chat
                    child: SidebarChatWidget(
                      onClose: () => setState(() => _isChatOpen = false),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFloatingButton({bool isDragging = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: isDragging ? null : () => setState(() => _isChatOpen = true),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          Icons.chat,
          color: isDark ? Colors.black : Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

class SidebarChatWidget extends StatefulWidget {
  final VoidCallback onClose;
  final bool showHeader;

  const SidebarChatWidget({super.key, required this.onClose, this.showHeader = true});

  @override
  State<SidebarChatWidget> createState() => _SidebarChatWidgetState();
}

class _SidebarChatWidgetState extends State<SidebarChatWidget> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _showSelector = false;
  bool _showingLectures = false;
  int _currentIndex = 0;
  
  // Sample names
  final List<String> _names = [
    'name1', 'name2', 'name3', 'name4', 'name5', 
    'name6', 'name7', 'name8', 'name9', 'name10'
  ];
  
  // Sample lectures
  final List<String> _lectures = [
    'lec1', 'lec2', 'lec3', 'lec4', 'lec5', 
    'lec6', 'lec7', 'lec8', 'lec9', 'lec10'
  ];
  
  @override
  void initState() {
    super.initState();
  }
  
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> handleUserMessage(String text) async {
    setState(() {
      _messages.add({"role": "user", "text": text});
      _isLoading = true;
    });
    _controller.clear();

    final reply = await ApiService.sendMessage(text);

    setState(() {
      _messages.add({"role": "assistant", "text": reply});
      _isLoading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: screenWidth > 600 ? 400 : screenWidth * 0.9,
      height: screenHeight > 600 ? 500 : screenHeight * 0.8,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF000000) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0xFF60A5FA).withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (conditionally shown)
          if (widget.showHeader)
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E3A8A),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat,
                      color: isDark ? Colors.black : Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Chat Assistant',
                    style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: isDark ? Colors.black : Colors.white, size: 20),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
          // Messages
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF1E3A8A)),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Thinking...",
                            style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF6B7280),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final msg = _messages[index];
                final isUser = msg["role"] == "user";

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: EdgeInsets.only(bottom: 8),
                    constraints: BoxConstraints(maxWidth: 250),
                    decoration: BoxDecoration(
                      color: isUser
                          ? (isDark
                              ? const Color(0xFF60A5FA)
                              : const Color(0xFF1E3A8A))
                          : (isDark
                              ? const Color(0xFF1A1A1A)
                              : const Color(0xFFF3F4F6)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg["text"] ?? "",
                      style: TextStyle(
                        color: isUser
                            ? (isDark ? Colors.black : Colors.white)
                            : (isDark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF374151)),
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Input
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? const Color(0xFF60A5FA).withValues(alpha: 0.3)
                      : const Color(0xFFE5E7EB),
                ),
              ),
            ),
            child: Column(
              children: [
                // Horizontal selector bar (appears above input)
                if (_showSelector)
                  Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: _buildHorizontalSelector(isDark),
                  ),
                // Input row
                Row(
                  children: [
                    // @ button
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF60A5FA), const Color(0xFF3B82F6)]
                              : [const Color(0xFF1E40AF), const Color(0xFF1E3A8A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E40AF)).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.alternate_email,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _showSelector = !_showSelector;
                            if (!_showSelector) {
                              _showingLectures = false;
                              _currentIndex = 0;
                            }
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: "Type a message...",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onSubmitted: (text) {
                          if (text.isNotEmpty && !_isLoading) {
                            handleUserMessage(text);
                          }
                        },
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.send,
                            color: isDark ? Colors.black : Colors.white, size: 18),
                        onPressed: _isLoading
                            ? null
                            : () {
                                if (_controller.text.isNotEmpty) {
                                  handleUserMessage(_controller.text);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSelector(bool isDark) {
    final currentList = _showingLectures ? _lectures : _names;
    final prefix = _showingLectures ? '' : '@';
    
    // Safety check for empty lists
    if (currentList.isEmpty) {
      return SizedBox(
        height: 50,
        child: Center(
          child: Text(
            'No items available',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    
    return GestureDetector(
      onPanUpdate: (details) {
        if (details.delta.dx > 5) {
          setState(() {
            _currentIndex = (_currentIndex - 1 + currentList.length) % currentList.length;
          });
        } else if (details.delta.dx < -5) {
          setState(() {
            _currentIndex = (_currentIndex + 1) % currentList.length;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark 
              ? const Color(0xFF1F2937).withValues(alpha: 0.8)
              : const Color(0xFFF9FAFB).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isDark 
                ? const Color(0xFF374151)
                : const Color(0xFFE5E7EB),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (index) {
            // Ensure _currentIndex is within bounds
            final safeCurrentIndex = _currentIndex.clamp(0, currentList.length - 1);
            final itemIndex = (safeCurrentIndex + index - 2 + currentList.length) % currentList.length;
            final item = currentList[itemIndex];
            final isSelected = index == 2; // Middle item is selected
            final opacity = isSelected ? 1.0 : (index == 1 || index == 3) ? 0.6 : 0.3;
            final scale = isSelected ? 1.0 : (index == 1 || index == 3) ? 0.9 : 0.8;
            
            return Expanded(
              child: Transform.scale(
                scale: scale,
                  child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: opacity,
                  child: GestureDetector(
                    onTap: () {
                      if (isSelected) {
                        if (_showingLectures) {
                          // Add lecture to text
                          _controller.text += ' $item';
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: _controller.text.length),
                          );
                          setState(() {
                            _showSelector = false;
                            _showingLectures = false;
                            _currentIndex = 0;
                          });
                        } else {
                          // Select name and switch to lectures
                          _controller.text = '$prefix$item ';
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: _controller.text.length),
                          );
                          setState(() {
                            _showingLectures = true;
                            _currentIndex = 0;
                          });
                        }
                      } else {
                        // Navigate to this item
                        setState(() {
                          _currentIndex = itemIndex;
                        });
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: isSelected
                            ? LinearGradient(
                                colors: isDark 
                                    ? [const Color(0xFF60A5FA), const Color(0xFF3B82F6)]
                                    : [const Color(0xFF1E40AF), const Color(0xFF1E3A8A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        color: !isSelected
                            ? (isDark 
                                ? const Color(0xFF374151).withValues(alpha: 0.3)
                                : const Color(0xFFE5E7EB).withValues(alpha: 0.5))
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected ? [
                          BoxShadow(
                            color: (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E40AF)).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ] : null,
                      ),
                      child: Center(
                        child: Text(
                          _showingLectures ? item : '$prefix$item',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : (isDark 
                                    ? const Color(0xFFE5E7EB)
                                    : const Color(0xFF374151)),
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
