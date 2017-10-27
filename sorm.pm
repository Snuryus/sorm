# mkdir /usr/abills/var/sorm/abonents/
# mkdir /usr/abills/var/sorm/payments/
# mkdir /usr/abills/var/sorm/wi-fi/
# mkdir /usr/abills/var/sorm/dictionaries/
# echo "2017-01-01 00:00:00" > /usr/abills/var/sorm/last_admin_action
# echo "2017-08-01 00:00:00" > /usr/abills/var/sorm/last_payments
#
# $conf{BILLD_PLUGINS} = 'sorm';
# $conf{ISP_ID} = '1'; # идентифакатор ИСП из "информация по операторам связи и их филалах"'
#
# iconv -f UTF-8 -t CP1251 abonents.csv.utf > abonents.csv


use strict;
use warnings FATAL => 'all';

our (
  %conf,
  $Admin,
  $db,
  $users,
  $Dv,
  $var_dir,
  $argv,
);

use Abills::Base qw/cmd _bp/;
use Abills::Misc qw/translate_list/;
use Users;
use Dv;
use Companies;
use Finance;
use Nas;

my $User = Users->new($db, $Admin, \%conf);
my $Company = Companies->new($db, $Admin, \%conf);
my $Payments = Finance->payments($db, $Admin, \%conf);
my $Nas = Nas->new($db, $Admin, \%conf);
my $isp_id = $conf{ISP_ID} || 1;
my $start_date = "01.08.2017 12:00:00";

if ($argv->{DICTIONARIES}) {
  # service_dictionary();
  payments_type_dictionary();
  docs_dictionary();
  gates_dictionary();
  ippool_dictionary();
}
elsif ($argv->{START}) {
  my $users_list = $User->list({
    COLS_NAME   => 1,
    PAGE_ROWS   => 99999,
  });
  
  foreach (@$users_list) {
    user_info_report($_->{uid});
  }
}
else {
  check_admin_actions();
  check_system_actions();
  check_payments();
}
print "-------\n";
send_changes();
print "+++++++++\n";


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
    PAGE_ROWS   => 99999,

    SORT        => 'p.date', 
    DESC        => 'DESC',
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

  my ($family, $name, $surname) = split (' ', $User->{FIO});

  my @arr;

  $arr[0] = $isp_id;                                    # идентификатор филиала (справочник филиалов)
  $arr[1] = $User->{LOGIN};                             # login
  $arr[2] = ($Dv->{IP} && $Dv->{IP} ne '0.0.0.0') ? $Dv->{IP} : "";  # статический IP
  $arr[3] = $User->{EMAIL};                             # e-mail
  $arr[4] = $User->{PHONE} || "";                       # телефон
  $arr[5] = "";                                         # MAC-адрес
  $arr[6] = _date_format($User->{REGISTRATION}) . ' 12:00:00';       # дата договора
  $arr[7] = $User->{CONTRACT_ID} || $User->{LOGIN};     # номер договора
  $arr[8] = $User->{DISABLE};                           # статус абонента (0 - подключен, 1 - отключен)
  $arr[9] = _date_format($User->{REGISTRATION}) . ' 12:00:00';        # дата активации основной услуги
  $arr[10] = ($User->{EXPIRE} ne '0000-00-00' && $User->{EXPIRE} lt $DATE) ? _date_format($User->{EXPIRE}) : ""; # дата отключения основной услуги

#физ лицо
  if (!$User->{COMPANY_ID}) {
     
     $arr[11] = 0;             # тип абонента (0 - физ лицо, 1 - юр лицо)

    my ($passport_num) = $User->{PASPORT_NUM} =~ m/(\d+)/;
    my ($passport_ser) = $User->{PASPORT_NUM} =~ m/(\D+)/;
    $passport_ser =~ s/\s//g if ($passport_ser);
    $User->{PASPORT_GRANT} =~ s/\n//g;
    $User->{PASPORT_GRANT} =~ s/\r//g;

    if ($name && $surname && $family) { 
      $arr[12] = '0';            # тип ФИО (0-структурировано, 1 - одной строкой) 
      $arr[13] = $name;          # имя
      $arr[14] = $surname;       # отчество
      $arr[15] = $family;        # фамилия
      $arr[16] = "";             # ФИО строкой
    }
    else {
      $arr[12] = '1';            # тип ФИО (0-структурировано, 1 - одной строкой) 
      $arr[13] = "";             # имя
      $arr[14] = "";             # отчество
      $arr[15] = "";             # фамилия
      $arr[16] = $User->{FIO};   # ФИО строкой
    }

    $arr[17] = "";             # дата рождения

    if ($passport_ser && $passport_num && $User->{PASPORT_GRANT}) {
      $arr[18] = '0';            # тип паспортных данных (0-структурировано, 1-одной строкой)
      $arr[19] = $passport_ser;  # серия паспорта
      $arr[20] = $passport_num;  # номер паспорта
      $arr[21] = $User->{PASPORT_GRANT} . " " . _date_format($User->{PASPORT_DATE});  # кем и когда выдан
      $arr[22] = "";             # паспортные данные строкой
    }
    else {
      $arr[18] = '1';            # тип паспортных данных (0-структурировано, 1-одной строкой)
      $arr[19] = "";             # серия паспорта
      $arr[20] = "";             # номер паспорта
      $arr[21] = "";             # кем и когда выдан
      $arr[22] = $User->{PASPORT_NUM} . " " . $User->{PASPORT_GRANT} . " " . $User->{PASPORT_DATE}; # паспортные данные строкой
    }
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
  $arr[43] = 1;               # тип данных адреса устройства (0 - структурировано, 1 - одной строкой)
  $arr[44] = "";              # индекс
  $arr[45] = "";              # страна
  $arr[46] = "";              # область
  $arr[47] = "";              # район
  $arr[48] = "";              # город
  $arr[49] = "";              # улица
  $arr[50] = "";              # дом
  $arr[51] = "";              # корпус
  $arr[52] = "";              # квартира
  $arr[53] = $address;        # адрес строкой


  my $string = "";
  foreach (@arr) {
    $string .= '"' . ($_ // "") . '";'; 
  }
  $string =~ s/;$/\n/;
  
  _add_report('user', $string);

  return 1;
}

#**********************************************************
=head2 ippool_dictionary($attr)

=cut
#**********************************************************
sub ippool_dictionary {

  my $pools_list = $Nas->nas_ip_pools_list({
    COLS_NAME   => 1,
    PAGE_ROWS   => 99999,
  });

  foreach my $pool (@$pools_list) {
    my $w=($pool->{ip}/16777216)%256;
    my $x=($pool->{ip}/65536)%256;
    my $y=($pool->{ip}/256)%256;
    my $ip = "$w.$x.$y.0";
    
    my $mask = 32 - length(sprintf ("%b", $pool->{ip_count}));

    my $string = '"' . $isp_id .'";'; 
    $string .= '"' . $pool->{pool_name} . '";';
    $string .= '"' . $ip . '";';
    $string .= '"' . $mask . '";';
    $string .= '"' . $start_date . '";';
    $string .= '""' . "\n";

    _add_report('pool', $string);
  }
print "IP pool dictionary formed.\n";
  return 1;
}

#**********************************************************
=head2 docs_dictionary($attr)

=cut
#**********************************************************
sub docs_dictionary {
  
  my $string = '"' . $isp_id .'";"1";"01.08.2017";"";"паспорт"' . "\n";
  _add_report('d_type', $string);

  print "Docs dictionary formed.\n";
  return 1;
}

#**********************************************************
=head2 gates_dictionary($attr)

=cut
#**********************************************************
sub gates_dictionary {
  
  my $string = '"' . $isp_id .'";"91.205.164.46";"01.08.2017";"";"Radius";"Россия";"Республика Крым";"Республика Крым";"г.Ялта";"ул. Соханя";"7";"7"' . "\n";
  _add_report('gates', $string);

  print "Gates dictionary formed.\n";
  return 1;
}

#**********************************************************
=head2 payments_type_dictionary($attr)

=cut
#**********************************************************
sub payments_type_dictionary {
  do ("/usr/abills/language/russian.pl");
  my $types = translate_list($Payments->payment_type_list({ COLS_NAME => 1 }));

  if ($conf{PAYSYS_PAYMENTS_METHODS}) {
    foreach my $line (split (';', $conf{PAYSYS_PAYMENTS_METHODS})) {
      my($id, $type) = split (':', $line);
      push (@$types, {id => $id, name => $type} );
    }
  }

  foreach (@$types) {
    my $string = '"' . $isp_id .'";';
    $string .= '"' . $_->{id} . '";';
    $string .= '"' . $start_date . '";';
    $string .= '"";';
    $string .= '"' . $_->{name} . '"' . "\n";
    _add_report('p_type', $string);
  }

  print "Payments types dictionary formed.\n";
  return 1;
}

#**********************************************************
=head2 nas_info_report($attr)

=cut
#**********************************************************
sub nas_dictionary {


  _add_report('p_type', '"1";');
}

#**********************************************************
=head2 payment_report($attr)

=cut
#**********************************************************
sub payment_report {
  my ($attr) = @_;

  $Dv->info($attr->{uid});
  my $ip = ($Dv->{IP} ne '0.0.0.0') ? $Dv->{IP} : "";
  
  my $string = '"' . $isp_id .'";';                             # идентификатор филиала из справочника
  $string   .= '"' . $attr->{method} . '";';                    # тип оплаты из сравочника
  $string   .= '"' . ($attr->{login} || "") . '";';             # номер договора
  $string   .= '"' . $ip . '";';                                # статический IP
  $string   .= '"' . _date_format($attr->{datetime}) . '";';    # дата пополнения
  $string   .= '"' . $attr->{sum} . '";';                       # сумма пополнения
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
print $string;
  my %reports = (
    user    => "$var_dir/sorm/abonents/abonents.csv.utf",
    payment => "$var_dir/sorm/payments/payments.csv.utf",
    p_type  => "$var_dir/sorm/dictionaries/pay-types.csv.utf",
    d_type  => "$var_dir/sorm/dictionaries/doc-types.csv.utf",
    gates   => "$var_dir/sorm/dictionaries/gates.csv.utf",
    pool    => "$var_dir/sorm/dictionaries/ip-numbering-plan.csv.utf",
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
=head2 _date_format($attr)

=cut
#**********************************************************
sub _date_format {
  my ($date) = @_;
  
  # (substr($date, 0, 4), substr($date, 6, 2)) = (substr($date, 8, 2), substr($date, 0, 4));
  # $date =~ s/\-/\./g;

  $date =~ s/(\d{4})-(\d{2})-(\d{2})(.*)/$3.$2.$1$4/;
  return $date;
}

#**********************************************************
=head2 send_changes($attr)

=cut
#**********************************************************
sub send_changes {
  
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/abonents/abonents.csv.utf > /usr/abills/var/sorm/abonents/abonents.csv') if (-e "/usr/abills/var/sorm/abonents/abonents.csv.utf");
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/payments/payments.csv.utf > /usr/abills/var/sorm/payments/payments.csv') if (-e "/usr/abills/var/sorm/payments/payments.csv.utf");
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/dictionaries/pay-types.csv.utf > /usr/abills/var/sorm/dictionaries/pay-types.csv') if (-e "/usr/abills/var/sorm/dictionaries/pay-types.csv.utf");
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/dictionaries/doc-types.csv.utf > /usr/abills/var/sorm/dictionaries/doc-types.csv') if (-e "/usr/abills/var/sorm/dictionaries/doc-types.csv.utf");
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/dictionaries/gates.csv.utf > /usr/abills/var/sorm/dictionaries/gates.csv') if (-e "/usr/abills/var/sorm/dictionaries/gates.csv.utf");
  # system('iconv -f UTF-8 -t CP1251 /usr/abills/var/sorm/dictionaries/ip-numbering-plan.csv.utf > /usr/abills/var/sorm/dictionaries/ip-numbering-plan.csv') if (-e "/usr/abills/var/sorm/dictionaries/ip-numbering-plan.csv.utf");

  return 1;
}


1