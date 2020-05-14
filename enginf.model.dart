import 'package:clientf/enginf_clientf_service/enginf.category.model.dart';
import 'package:clientf/enginf_clientf_service/enginf.category_list.model.dart';
import 'package:clientf/enginf_clientf_service/enginf.defines.dart';
import 'package:clientf/enginf_clientf_service/enginf.error.model.dart';
import 'package:clientf/enginf_clientf_service/enginf.post.model.dart';
import 'package:clientf/enginf_clientf_service/enginf.user.model.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 파이어베이스 백엔드(`Firebase Clould Functions`)와 통신을 관리하는 주요 모델
///
/// ChangeNotifier 를 상속하여 State 관리에 사용 할 수 있다.
class EngineModel extends ChangeNotifier {
  /// 사용자가 로그인을 하면, 사용자 정보를 가진다. 로그인을 안한 상태이면 null.
  FirebaseUser user;

  /// 파이어베이스 로그인을 연결하는 플러그인.
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 구글 로그인을 연결하는 플러그인.
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// 생성자에서 초기화를 한다.
  EngineModel() {
    /// 사용자가 로그인/로그아웃을 할 때 `user` 를 업데이트하고 notifyListeners() 를 호출.
    (() async {
      _auth.onAuthStateChanged.listen((_user) {
        user = _user;
        notifyListeners();
      });
    })();
  }

  /// 백엔드로 호출하는 함수. 에러가 있으면 에러를 throw 한다.
  Future<dynamic> callFunction(Map<String, dynamic> request) async {
    final HttpsCallable callable = CloudFunctions.instance.getHttpsCallable(
      functionName: 'router',
    );
    HttpsCallableResult callableResult = await callable.call(request);

    var result;

    try {
      result = callableResult.data;
    } catch (e) {
      /// Error happened when calling Callable funtions. This should never happens.
      throw 'Error at allableResult.data EngineModel::callFunctions()';
    }

    /// 백엔드로 부터 받은 값이 에러이면 throw 를 하고, 아니면 값을 리턴.
    ///
    /// 백엔드로 부터 받은 값은 항상 Map 이나 List 이다. 숫자나 문자와 같은 단일(스칼라)값이 아니다.
    /// 벡엔드로 부터 받은 값이 에러이면, `error` 속성에 `true`의 값이 들어있다.
    if (result is Map && result['error'] == true) {
      throw EngineError.fromMap(result);
    } else {
      return result;
    }
  }

  /// 사용자가 로그인을 했으면 참을 리턴
  bool get loggedIn {
    return user != null;
  }

  /// 사용자가 로그인을 안했으면 참을 리턴.
  bool get notLoggedIn {
    return loggedIn == false;
  }

  /// 사용자 로그인을 한다.
  ///
  /// `Firebase Auth` 를 바탕으로 로그인을 한다.
  /// 에러가 있으면 에러를 throw 하고,
  //  /// 로그인이 성공하면 `notifiyListeners()`를 한 다음, `FirebaseUser` 객체를 리턴한다.
  //  /// 주의 할 것은 `user` 변수는 이 함수에서 직접 업데이트 하지 않고 `onAuthStateChanged()`에서 자동 감지를 해서 업데이트 한다.
  Future<FirebaseUser> loginWithEmailAndPassword(
      String email, String password) async {
    if (email == null || email == '') {
      throw INPUT_EMAIL;
    }
    if (password == null || password == '') {
      throw INPUT_PASSWORD;
    }
    try {
      AuthResult result = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (result.user != null) {
        notifyListeners();
        return result.user;
      } else {
        throw ERROR_USER_IS_NULL;
      }
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      throw code;
    } catch (e) {
      throw e.message;
    }
  }

  /// 'googleAuth'의 Credential 과 `Firebase Auth` 를 바탕으로 로그인을 한다.
  /// 에러가 있으면 에러를 throw 하고,
  //  /// 로그인이 성공하면 `notifiyListeners()`를 한 다음, `FirebaseUser` 객체를 리턴한다.
  //  /// 주의 할 것은 `user` 변수는 이 함수에서 직접 업데이트 하지 않고 `onAuthStateChanged()`에서 자동 감지를 해서 업데이트 한다.
  Future<FirebaseUser> loginWithGoogleAccount() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.getCredential(
          idToken: googleAuth.idToken,
          accessToken: googleAuth.accessToken
      );

      AuthResult result = await _auth.signInWithCredential(credential);
      if (result.user != null) {
        notifyListeners();
        return result.user;
      } else {
        throw ERROR_USER_IS_NULL;
      }
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      throw code;
    } catch (e) {
      throw e.message;
    }
  }

  /// 사용자 로그아웃을 하고 `notifyListeners()` 를 한다. `user` 는 Listeners 에서 자동 업데이트된다.
  logout() async {
    await _auth.signOut();
    // 구글로그인이 되어 있었다면 로그아웃을 진행한다.
    if(_googleSignIn.currentUser != null){
      await _googleSignIn.signOut();
    }
    notifyListeners();
  }

  /// 회원 가입을 한다.
  ///
  /// 백엔드로 회원 가입 정보를 보내면, 백엔드에서 `Firebase Auth`에 계정을 생성하고, 추가 정보를 `Firestore` 에 저장한다.
  /// 에러가 있으면 throw 를 한다.
  Future<FirebaseUser> register(data) async {
    var registeredUser = await callFunction(
      {'route': 'user.register', 'data': data},
    );
    final loggedUser = await loginWithEmailAndPassword(
        registeredUser['email'], data['password']);
    return loggedUser;
  }

  /// 사용자 정보 업데이트를 한다.
  ///
  /// 기본적으로 `displayName`, `photoUrl`, `phoneNumber` 의 속성이 있는데 이 것들으 `Firebase Auth` 에 저장된다.
  /// 그 외 추가적으로 저장하는 값은 `Firestore`에 저장된다.
  /// 참고로 회원 가입/수정을 할 때에 얼마든지 값(속성)을 추가로 지정 할 수 있다(제한이 없다).
  Future<EngineUser> update(data) async {
    data['uid'] = user.uid;
    var update = await callFunction(
      {'route': 'user.update', 'data': data},
    );
    await user.reload();
    user = await _auth.currentUser();
    notifyListeners();
    return EngineUser.fromMap(update);
  }

  /// 회원 정보를 가져온다.
  ///
  /// 회원 로그인은 백엔드를 통하지 않고 `Firebase Auth` 플러그인을 이용하여 바로 로그인을 한다.
  /// 이 때, `Firebase User` 가 가지는 `displayName`, `photoUrl`, `phoneNumber` 를 그대로 사용 할 수 있지만, 그 외의 추가 정보는 없다.
  /// 이 함수를 이용하여 `displayName`, `photoUrl`, `phoneNumber` 뿐만아니라 추가적으로 지정한 모든 값을 다 가져 올 수 있다.
  /// 즉, 회원 정보 수정을 할 때에 이 함수를 이용해서 모든 정보를 불러와서 업데이트 양식(form)에 보여주면 되는 것이다.
  Future<EngineUser> profile() async {
    if (notLoggedIn || user?.uid == null) throw LOGIN_FIRST;
    final profile =
        await callFunction({'route': 'user.data', 'data': user.uid});
    return EngineUser.fromMap(profile);
  }

  /// 카테로리를 생성한다. 관리자만 가능.
  Future categoryCreate(data) {
    return callFunction({'route': 'category.create', 'data': data});
  }

  /// 카테고리를 업데이트한다. 관리자만 가능.
  Future categoryUpdate(data) {
    return callFunction({'route': 'category.update', 'data': data});
  }

  /// 카테고리 하나의 정보를 가져온다.
  Future<EngineCategory> categoryData(String id) async {
    var re = await callFunction({'route': 'category.data', 'data': id});
    return EngineCategory.fromEnginData(re);
  }

  /// 카테고리 목록 전체를 가져온다.
  Future<EngineCategoryList> categoryList() async {
    return EngineCategoryList.fromEnginData(
        await callFunction({'route': 'category.list'}));
  }

  /// 게시글 생성
  ///
  /// 입력값은 프로토콜 문서 참고
  Future<EnginePost> postCreate(data) async {
    final post = await callFunction({'route': 'post.create', 'data': data});
    return EnginePost.fromEnginData(post);
  }

  /// 게시글 수정
  ///
  /// 입력값은 프로토콜 문서 참고
  Future<EnginePost> postUpdate(data) async {
    final post = await callFunction({'route': 'post.update', 'data': data});
    return EnginePost.fromEnginData(post);
  }

  /// 게시글 삭제
  ///
  /// 입력값은 프로토콜 문서 참고
  Future<EnginePost> postDelete(String id) async {
    final post = await callFunction({'route': 'post.delete', 'data': id});
    return EnginePost.fromEnginData(post);
  }

  /// 게시글 목록
  ///
  /// 입력값은 프로토콜 문서 참고
  Future<List<EnginePost>> postList(data) async {
    final List posts = await callFunction({'route': 'post.list', 'data': data});

    List<EnginePost> ret = [];
    for (var e in posts) {
      ret.add(EnginePost.fromEnginData(e));
    }
    return ret;
  }

  /// 코멘트 생성
  ///
  /// * 입력값은 프로토콜 문서 참고
  /// * postCreate(), postUpdate() 와는 달리 자동으로 EngineComment 로 변환하지 않는다.
  ///   이유는 백엔드로 부터 데이터를 가져 왔을 때, 곧바로 랜더링 준비를 하면(Model 호출 등) 클라이언트에 무리를 줄 수 있다.
  ///   미리 하지 말고 필요(랜더링)할 때, 그 때 준비해서 해당 작업을 하면 된다.
  /// * 코멘트를 백엔드로 가져 올 때, 랜더링 준비를 하지 않으므로, 여기서도 하지 않는다.
  Future<Map<dynamic, dynamic>> commentCreate(data) async {
    final comment =
        await callFunction({'route': 'comment.create', 'data': data});
    return comment;
    // return EngineComment.fromEnginData(comment);
  }

  /// 코멘트 수정
  ///
  /// * 입력값은 프로토콜 문서 참고
  /// * commentCreate() 의 설명을 참고.
  Future<Map<dynamic, dynamic>> commentUpdate(data) async {
    final comment =
        await callFunction({'route': 'comment.update', 'data': data});
    return comment;
    // return EngineComment.fromEnginData(comment);
  }

  /// 코멘트 삭제
  ///
  /// * 입력값은 프로토콜 문서 참고
  Future commentDelete(String id) async {
    final deleted = await callFunction({'route': 'comment.delete', 'data': id});
    return deleted;
  }
}
