# mkdir /usr/abills/var/sorm/abonents/
# mkdir /usr/abills/var/sorm/payments/
# mkdir /usr/abills/var/sorm/wi-fi/
# mkdir /usr/abills/var/sorm/dictionaries/
# echo "2017-01-01 00:00:00" > /usr/abills/var/sorm/last_admin_action
# echo "2017-01-01 00:00:00" > /usr/abills/var/sorm/last_payments
#
# $conf{BILLD_PLUGINS}='sorm';
#


use strict;
use warnings FATAL => 'all';

our (
  %conf,
  $Admin,
  $db,
  $users,
  $Dv,
  $var_dir
);

use Abills::Base qw/cmd _bp/;
use Users;
use Dv;
use Companies;
use Finance;

my $User = Users->new($db, $Admin, \%conf);
my $Company = Companies->new($db, $Admin, \%conf);
my $Payments = Finance->payments($db, $Admin, \%conf);

check_admin_actions();
check_system_actions();
check_payments();

send_changes();


#**********************************************************
=head2 check_admin_actions($attr)

=cut
#**********************************************************
sub check_admin_actions {

  my $filename = $var_dir . "sorm/last_admin_action";
  open (my $fh, '<', $filename) or die "Could not open file '$filename' $!";
  my $last_action_date = <$fh>;
  chomp $last_action_date;
  close $fh;

  my $action_list = $Admin->action_list({ 
    COLS_NAME => 1, 
    DATETIME  => ">$last_action_date", 
    SORT      => 'aa.datetime', 
    DESC      => 'DESC',
  });
  
  return 1 if ($Admin->{TOTAL} < 1);

  $last_action_date = $action_list->[0]->{datetime} . "\n";

  foreach my $action (@$action_list) {
    user_info_report($action->{uid}) if ($action->{uid});
  }
  
  open ($fh, '>', $filename) or die "Could not open file '$filename' $!";
  print $fh $last_action_date;
  close $fh;

  return 1;
}

#**********************************************************
=head2 check_system_actions($attr)

=cut
#**********************************************************
sub check_system_actions {
  return 1;
}

#**********************************************************
=head2 check_payments($attr)

=cut
#**********************************************************
sub check_payments {

  my $filename = $var_dir . "sorm/last_payments";
  open (my $fh, '<', $filename) or die "Could not open file '$filename' $!";
  my $last_payment_date = <$fh>;
  chomp $last_payment_date;
  close $fh;

  my $payment_list = $Payments->list({
    DATETIME    => ">$last_payment_date",
    SUM         => '_SHOW',
    METHOD      => '_SHOW',
    CONTRACT_ID => '_SHOW',
    UID         => '_SHOW',

    COLS_NAME   => 1,
  });
  
  return 1 if ($Payments->{TOTAL} < 1);

  $last_payment_date = $payment_list->[0]->{datetime} . "\n";

  foreach my $payment (@$payment_list) {
    payment_report($payment);
  }
  
  open ($fh, '>', $filename) or die "Could not open file '$filename' $!";
  print $fh $last_payment_date;
  close $fh;

  return 1;
}

#**********************************************************
=head2 user_info_report($uid)

=cut
#**********************************************************
sub user_info_report {
  my ($uid) = @_;

  $User->pi({ UID => $uid });
  $User->info($uid);
  $Dv->info($uid);

  my @arr;
  
  $arr[0] = 1;                                          # идентификатор филиала (справочник филиалов)
  $arr[1] = $User->{LOGIN};                             # login
  $arr[2] = ($Dv->{IP} ne '0.0.0.0') ? $Dv->{IP} : "";  # статический IP
  $arr[3] = $User->{EMAIL};                             # e-mail
  $arr[4] = $User->{PHONE};                             # телефон
  $arr[5] = $Dv->{CID};                                 # MAC-адрес
  $arr[6] = $User->{CONTRACT_DATE};                     # дата договора
  $arr[7] = $User->{CONTRACT_ID};                       # номер договора
  $arr[8] = $User->{DISABLE};                           # статус абонента (0 - подключен, 1 - отключен)
  $arr[9] = $User->{REGISTRATION};                      # дата активации основной услуги
  $arr[10] = ($User->{EXPIRE} ne '0000-00-00' && $User->{EXPIRE} lt $DATE) ? $User->{EXPIRE} : ""; # дата отключения основной услуги

#физ лицо
  if (!$User->{COMPANY_ID}) {
     
     $arr[11] = 0;             # тип абонента (0 - физ лицо, 1 - юр лицо)

    my $passport = "";
    if ($User->{PASPORT_NUM} && $User->{PASPORT_GRANT} && $User->{PASPORT_DATE}) {
      $passport = $User->{PASPORT_NUM} . " " . $User->{PASPORT_GRANT} . " " . $User->{PASPORT_DATE};
    }
    else {
      print "No passport info for UID : $uid\n";
    }

    $arr[12] = 1;              # тип ФИО (0-структурировано, 1 - одной строкой) 
    $arr[13] = "";             # имя
    $arr[14] = "";             # отчество
    $arr[15] = "";             # фамилия
    $arr[16] = $User->{FIO};   # ФИО строкой
    $arr[17] = "";             # дата рождения
    $arr[18] = 1;              # тип паспортных данных (0-структурировано, 1-одной строкой)
    $arr[19] = "";             # серия паспорта
    $arr[20] = "";             # номер паспорта
    $arr[21] = "";             # кем и когда выдан
    $arr[22] = $passport;      # паспортные данные строкой
    $arr[23] = 1;              # тип документа (спровочник видов документов)
    $arr[24] = "";             # банк абонента
    $arr[25] = "";             # номер счета абонента

    $arr[26] = "";             # 
    $arr[27] = "";             # 
    $arr[28] = "";             # поля остаются пустыми если абонент физ. лицо
    $arr[29] = "";             # 
    $arr[30] = "";             # 
    $arr[31] = "";             # 
  }

#юр лицо
  else {

    $arr[11] = 1;              # тип абонента (0 - физ лицо, 1 - юр лицо)

    $arr[12] = "";             # 
    $arr[13] = "";             # 
    $arr[14] = "";             # 
    $arr[15] = "";             # 
    $arr[16] = "";             # 
    $arr[17] = "";             # 
    $arr[18] = "";             # 
    $arr[19] = "";             # поля остаются пустыми если абонент юр. лицо
    $arr[20] = "";             # 
    $arr[21] = "";             # 
    $arr[22] = "";             # 
    $arr[23] = "";             # 
    $arr[24] = "";             # 
    $arr[25] = "";             # 

    $Company->info($User->{COMPANY_ID});

    $arr[26] = $Company->{COMPANY_NAME};   # наименование компании
    $arr[27] = $Company->{COMPANY_VAT};    # ИНН
    $arr[28] = $Company->{REPRESENTATIVE}; # контактное лицо
    $arr[29] = $Company->{PHONE};          # контактный телефон
    $arr[30] = $Company->{BANK_NAME};      # банк абонента
    $arr[31] = $Company->{BANK_ACCOUNT};   # номер счета абонента
  }

#адрес абонента  
  my $address = ($User->{ADDRESS_FULL} || "") . ", " . ($User->{CITY} || "") . ", " . ($User->{ZIP} || "");

  $arr[32] = 1;               # тип данных адреса (0 - структурировано, 1 - одной строкой)
  $arr[33] = "";              # индекс
  $arr[34] = "";              # страна
  $arr[35] = "";              # область
  $arr[36] = "";              # район
  $arr[37] = "";              # город
  $arr[38] = "";              # улица
  $arr[39] = "";              # дом
  $arr[40] = "";              # корпус
  $arr[41] = "";              # квартира
  $arr[42] = $address;        # адрес строкой

#адрес устройства
  $arr[43] = "";               # тип данных адреса устройства (0 - структурировано, 1 - одной строкой)
  $arr[44] = "";              # индекс
  $arr[45] = "";              # страна
  $arr[46] = "";              # область
  $arr[47] = "";              # район
  $arr[48] = "";              # город
  $arr[49] = "";              # улица
  $arr[50] = "";              # дом
  $arr[51] = "";              # корпус
  $arr[52] = "";              # квартира
  $arr[53] = "";              # адрес строкой


  my $string = "";
  foreach (@arr) {
    $string .= '"' . ($_ // "") . '";'; 
  }
  $string =~ s/;$/\n/;
  
  _add_report('user', $string);

  return 1;
}

#**********************************************************
=head2 service_report($attr)

convert 01.02.17 to 2017-02-01

=cut
#**********************************************************
sub service_report {
  return 1;
}

#**********************************************************
=head2 nas_info_report($attr)

=cut
#**********************************************************
sub nas_info_report {
  return 1;
}

#**********************************************************
=head2 payment_report($attr)

=cut
#**********************************************************
sub payment_report {
  my ($attr) = @_;

  $Dv->info($attr->{uid});
  my $ip = ($Dv->{IP} ne '0.0.0.0') ? $Dv->{IP} : "";
  
  my $string = '"1";';                            # идентификатор филиала из справочника
  $string   .= '"' . $attr->{method} . '";';      # тип оплаты из сравочника
  $string   .= '"' . ($attr->{contract_id} || "") . '";'; # номер договора
  $string   .= '"' . $ip . '";';                  # статический IP
  $string   .= '"' . $attr->{datetime} . '";';    # дата пополнения
  $string   .= '"' . $attr->{sum} . '";';         # сумма пополнения
  $string   .= '"' . ($attr->{dsc} || "") . '"' . "\n";         # дополнительная информация

  _add_report('payment', $string);

  return 1;
}

#**********************************************************
=head2 _add_user_change($type, $string)

=cut
#**********************************************************
sub _add_report {
  my ($type, $string) = @_;

  my %reports = (
    user    => "$var_dir/sorm/abonents/abonents.csv",
    payment => "$var_dir/sorm/payments/payments.csv",
  );

  my $filename = $reports{$type};

  if ($type ne 'payment' && -e $filename) {
    open (my $fh, '<', $filename) or die "Could not open file '$filename' $!";
    while (<$fh>) {
      return 1 if ($_ eq $string);
    }
    close $fh;
  }

  open (my $fh, '>>', $filename) or die "Could not open file '$filename' $!";
  print $fh $string;
  close $fh;

  return 1;
}

#**********************************************************
=head2 send_changes($attr)

=cut
#**********************************************************
sub send_changes {
  return 1;
}