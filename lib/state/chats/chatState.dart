import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_twitter_clone/helper/constant.dart';
import 'package:flutter_twitter_clone/helper/enum.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_twitter_clone/model/chatModel.dart';
import 'package:flutter_twitter_clone/helper/utility.dart';
import 'package:flutter_twitter_clone/model/user.dart';
import 'package:flutter_twitter_clone/state/appState.dart';

import '../../helper/utility.dart';

class ChatState extends AppState {
  List<ChatMessage> _messageList;
  User _chatUser;
  String serverToken = "<FCM SERVER KEY>";
  StreamSubscription<QuerySnapshot> _messageSubscription;
  static final CollectionReference _messageCollection =
      kfirestore.collection(MESSAGES_COLLECTION);

  static final CollectionReference _userCollection =
      kfirestore.collection(USERS_COLLECTION);

  /// Get FCM server key from firebase project settings
  User get chatUser => _chatUser;
  set setChatUser(User model) {
    _chatUser = model;
  }

  String _channelName;
  // Query messageQuery;

  /// Contains list of chat messages on main chat screen
  /// List is sortBy mesage timeStamp
  /// Last message will be display on the bottom of screen
  List<ChatMessage> get messageList {
    if (_messageList == null) {
      return null;
    } else {
      _messageList.sort((x, y) => DateTime.parse(y.createdAt)
          .toLocal()
          .compareTo(DateTime.parse(x.createdAt).toLocal()));
      return _messageList;
    }
  }

  void databaseInit(String userId, String myId) async {
    _messageList = null;

    getChannelName(userId, myId);

    _messageSubscription = _messageCollection
        .document(_channelName)
        .collection(MESSAGES_COLLECTION)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      if (snapshot.documentChanges.isEmpty) {
        return;
      }
      if (snapshot.documentChanges.first.type == DocumentChangeType.added) {
        _onMessageAdded(snapshot.documentChanges.first.document);
      } else if (snapshot.documentChanges.first.type ==
          DocumentChangeType.removed) {
        // _onNotificationRemoved(snapshot.documentChanges.first.document);
      } else if (snapshot.documentChanges.first.type ==
          DocumentChangeType.modified) {
        _onMessageChanged(snapshot.documentChanges.first.document);
      }
    });
  }

  /// Fecth FCM server key from firebase Remote config
  /// FCM server key is stored in firebase remote config
  /// you have to add server key in firebase remote config
  /// To fetch this key go to project setting in firebase
  /// Click on `cloud messaging` tab
  /// Copy server key from `Project credentials`
  /// Now goto `Remote Congig` section in fireabse
  /// Add [FcmServerKey]  as paramerter key and below json in Default vslue
  ///  ``` json
  ///  {
  ///    "key": "FCM server key here"
  ///  } ```
  /// For more detail visit:- https://github.com/TheAlphamerc/flutter_twitter_clone/issues/28#issue-611695533
  /// For package detail check:-  https://pub.dev/packages/firebase_remote_config#-readme-tab-
  void getFCMServerKey() async {
    final RemoteConfig remoteConfig = await RemoteConfig.instance;
    await remoteConfig.fetch(expiration: const Duration(days: 5));
    await remoteConfig.activateFetched();
    var data = remoteConfig.getString('FcmServerKey');
    if (data != null && data.isNotEmpty) {
      serverToken = jsonDecode(data)["key"];
    } else {
      cprint("Please configure Remote config in firebase",
          errorIn: "getFCMServerKey");
    }
  }

  /// Fetch chat  all chat messages
  /// `_channelName` is used as primary key for chat message table
  /// `_channelName` is created from  by combining first 5 letters from user ids of two users
  void getchatDetailAsync() async {
    try {
      // _messageList.clear();
      if (_messageList == null) {
        _messageList = [];
      }
      _messageCollection
          .document(_channelName)
          .collection(MESSAGES_COLLECTION)
          .getDocuments()
          .then((QuerySnapshot querySnapshot) {
        if (querySnapshot != null && querySnapshot.documents.isNotEmpty) {
          for (var i = 0; i < querySnapshot.documents.length; i++) {
            final model = ChatMessage.fromJson(querySnapshot.documents[i].data);
            model.key = querySnapshot.documents[i].documentID;
            _messageList.add(model);
          }
          // _userlist.addAll(_userFilterlist);
          // _userFilterlist.sort((x, y) => y.followers.compareTo(x.followers));
          notifyListeners();
        } else {
          _messageList = null;
        }
      });
      // kDatabase
      //     .child('chats')
      //     .child(_channelName)
      //     .once()
      //     .then((DataSnapshot snapshot) {
      //   _messageList = List<ChatMessage>();
      //   if (snapshot.value != null) {
      //     var map = snapshot.value;
      //     if (map != null) {
      //       map.forEach((key, value) {
      //         var model = ChatMessage.fromJson(value);
      //         model.key = key;
      //         _messageList.add(model);
      //       });
      //     }
      //   } else {
      //     _messageList = null;
      //   }
      // });
    } catch (error) {
      cprint(error);
    }
  }

  void onMessageSubmitted(ChatMessage message, {User myUser, User secondUser}) {
    print(chatUser.userId);
    try {
      if (message.message != null &&
          message.message.length > 0 &&
          message.message.length < 400) {
        _userCollection
            .document(message.senderId)
            .collection(CHAT_USER_LIST_COLLECTION)
            .document(message.receiverId)
            .setData({"lastMessage": message.toJson()});
        _userCollection
            .document(message.receiverId)
            .collection(CHAT_USER_LIST_COLLECTION)
            .document(message.senderId)
            .setData({"lastMessage": message.toJson()});

        kfirestore
            .collection(MESSAGES_COLLECTION)
            .document(_channelName)
            .collection(MESSAGES_COLLECTION)
            .document()
            .setData(message.toJson());
        // sendAndRetrieveMessage(message);
        logEvent('send_message');
      }
    } catch (error) {
      cprint(error);
    }
  }

  String getChannelName(String user1, String user2) {
    user1 = user1.substring(0, 5);
    user2 = user2.substring(0, 5);
    List<String> list = [user1, user2];
    list.sort();
    _channelName = '${list[0]}-${list[1]}';
    // cprint(_channelName); //2RhfE-5kyFB
    return _channelName;
  }

  void _onMessageAdded(DocumentSnapshot snapshot) {
    if (_messageList == null) {
      _messageList = List<ChatMessage>();
    }
    if (snapshot.data != null) {
      var map = snapshot.data;
      if (map != null) {
        var model = ChatMessage.fromJson(map);
        model.key = snapshot.documentID;
        if (_messageList.length > 0 &&
            _messageList.any((x) => x.key == model.key)) {
          return;
        }
        _messageList.add(model);
      }
    } else {
      _messageList = null;
    }
    notifyListeners();
  }

  void _onMessageChanged(DocumentSnapshot snapshot) {
    if (_messageList == null) {
      _messageList = List<ChatMessage>();
    }
    if (snapshot.data != null) {
      var map = snapshot.data;
      if (map != null) {
        var model = ChatMessage.fromJson(map);
        model.key = snapshot.documentID;
        if (_messageList.length > 0 &&
            _messageList.any((x) => x.key == model.key)) {
          return;
        }
        _messageList.add(model);
      }
    } else {
      _messageList = null;
    }
    notifyListeners();
  }

  void onChatScreenClosed() {
    if (_messageSubscription != null) {
      _messageSubscription.cancel();
    }
    // if (_chatUserList != null && _chatUserList.isNotEmpty) {
    //   var user = _chatUserList.firstWhere((x) => x.key == chatUser.userId);
    //   if (_messageList != null) {
    //     user.message = _messageList.first.message;
    //     user.createdAt = _messageList.first.createdAt; //;
    //     _messageList = null;
    //     notifyListeners();
    //   }
    // }
  }

  @override
  void dispose() {
    _messageSubscription.cancel();
    super.dispose();
  }

  final FirebaseMessaging firebaseMessaging = FirebaseMessaging();

  void sendAndRetrieveMessage(ChatMessage model) async {
    /// on noti
    await firebaseMessaging.requestNotificationPermissions(
      const IosNotificationSettings(
          sound: true, badge: true, alert: true, provisional: false),
    );
    if (chatUser.fcmToken == null) {
      return;
    }

    var body = jsonEncode(<String, dynamic>{
      'notification': <String, dynamic>{
        'body': model.message,
        'title': "Message from ${model.senderName}"
      },
      'priority': 'high',
      'data': <String, dynamic>{
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'id': '1',
        'status': 'done',
        "type": NotificationType.Message.toString(),
        "senderId": model.senderId,
        "receiverId": model.receiverId,
        "title": "title",
        "body": model.message,
        "tweetId": ""
      },
      'to': chatUser.fcmToken
    });
    var response = await http.post('https://fcm.googleapis.com/fcm/send',
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverToken',
        },
        body: body);
    print(response.body.toString());
  }
}
