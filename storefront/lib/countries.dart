import 'package:retail_pos/core/widgets/phone_field.dart';

export 'package:retail_pos/core/widgets/phone_field.dart'
    show
        DialCountry,
        PhoneField,
        countryName,
        dialCountries,
        dialCountry,
        flagStyle,
        formatPhone,
        showCountryPicker,
        splitPhone;

/// Phone step state kept while the visitor moves from the number to the code.
class LoginDraft {
  String iso = 'HT';
  String national = '';
  String signupToken = '';

  DialCountry get country => dialCountry(iso);

  String get displayPhone {
    final digits = national.replaceAll(RegExp(r'\D'), '');
    return '+${country.dial} $digits';
  }

  void clear() {
    iso = 'HT';
    national = '';
    signupToken = '';
  }
}

final loginDraft = LoginDraft();
