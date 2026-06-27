import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:padue/features/auth/models/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

 // Sign in with email and password
  Future<User?> signInWithCredentials(String email, String password) async {
    try {
     // print('Signing in with: $email');
      UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = cred.user;
      if (user != null) {
     //   print('Signed in: ${user.uid}');
        await setUserRole('user'); // Default role for regular users
        return user;
      }
      throw Exception('Sign-in failed');
    } catch (e) {
    //  print('Sign-in failed: $e');
      rethrow;
    }
  }

  // Sign up with email and password
  Future<User?> signUpWithCredentials(String email, String password) async {
    try {
    //  print('Signing up with: $email');
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = cred.user;
      if (user != null) {
        // Create a basic user profile in Firestore
        UserProfile profile = UserProfile(
          uid: user.uid,
          phoneNumber: '', // No phone support in this simplified version
          name: null,
          emergencyContact: null,
          profilePicUrl: null,
          deviceToken: null,
          adFree: false,
          priorityUntil: null,
          lastActive: DateTime.now(),
        );
        await _firestore.collection('users').doc(user.uid).set({
          ...profile.toMap(),
          'email': email,
          'role': 'user', // Default role
        });

        // Send email verification
        if (!user.emailVerified) {
          await user.sendEmailVerification();
        }

       // print('Registered and signed in: ${user.uid}');
        await setUserRole('user');
        return user;
      }
      throw Exception('Sign-up failed');
    } catch (e) {
   //   print('Sign-up failed: $e');
      rethrow;
    }
  }

  // Other methods remain unchanged (e.g., providerSignIn, providerSignUp, sendPasswordResetEmail, etc.)
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
     // print('Password reset failed: $e');
      rethrow;
    }
  }


  // Provider Sign-up with email verification
  Future<User?> providerSignUp(String email, String password) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = cred.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
      return user;
    } catch (e) {
    //  print('Provider sign-up failed: $e');
      rethrow;
    }
  }

  // Provider Sign-in
  Future<User?> providerSignIn(String email, String password) async {
    UserCredential cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return cred.user;
  }

 

  // Phone verification methods (unchanged)
  Future<void> verifyPhoneNumber(String phoneNumber, Function(String) onCodeSent) async {
  //  print('Sending OTP to: $phoneNumber');
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
       // print('Auto-verification completed: ${credential.smsCode}');
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
      //  print('Verification failed: ${e.code} - ${e.message}');
        throw e;
      },
      codeSent: (String verificationId, int? resendToken) {
     //   print('Code sent, verificationId: $verificationId');
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
     //   print('Auto-retrieval timeout: $verificationId');
      },
    );
  }

  Future<User?> verifyOtp(String verificationId, String smsCode) async {
    try {
    //  print('verifyOtp called with: verificationId=$verificationId, smsCode=$smsCode');
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      UserCredential userCredential = await _auth.signInWithCredential(credential);
    //  print('Sign-in successful, user: ${userCredential.user?.uid}');
      return userCredential.user;
    } catch (e) {
   //   print('Error verifying OTP: $e');
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<String?> getUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  Future<void> setUserRole(String role) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
  }
}