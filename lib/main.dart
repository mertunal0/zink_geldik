import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:zinkgeldik/Globals.dart' as Globals;
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:workmanager/workmanager.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Ana_Sayfa(),
  ));
}

void callbackDispatcher()
{
  Workmanager().executeTask((taskName, inputData) async {

    return Future.value(true);
  });
}

class Lokal_Veritabani
{
  Future<String> get lokal_path async {
    final directory = await getApplicationDocumentsDirectory();

    return directory.path;
  }

  Future<File> get lokal_dosya async {
    final path = await lokal_path;
    return File('$path/hat_ve_durak_bilgileri.json');
  }

  Future<String> Hat_Durak_Bilgilerini_Lokalden_Oku() async {
    try {
      final file = await lokal_dosya;

      // Read the file
      final contents = await file.readAsString();

      return contents;
    } catch (e) {
      // If encountering an error, return 0
      return "okuma_hatasi";
    }
  }

  Future<File> Hat_Durak_Bilgilerini_Lokale_Yaz(String yazilacak_dosya) async {
    final file = await lokal_dosya;

    // Write the file
    return file.writeAsString(yazilacak_dosya);
  }

}

class Ana_Sayfa extends StatefulWidget {
  @override
  _Ana_SayfaState createState() => _Ana_SayfaState();
}

class _Ana_SayfaState extends State<Ana_Sayfa> {

  late final FirebaseApp fb_app;

  final Lokal_Veritabani lokal_db = Lokal_Veritabani();

  TextEditingController durak_arama_controller = TextEditingController();
  PanelController acilir_panel_kontroller = PanelController();

  var istanbul_tum_hatlar = [];
  var renderlanacak_hat_list = [];
  var renderlanacak_durak_list = [];

  int secili_hat_idx = 0;
  int secili_durak_idx = 0;

  String hat_arama_edit_text_deger = "";
  bool   hat_arama_dropdown_visibility = false;
  String durak_arama_edit_text_deger = "";
  bool   durak_arama_edit_text_aktiflik = false;

  late GoogleMapController harita_kontrolcusu;

  Marker kullanici_marker       = Marker(markerId: MarkerId("kullanici_marker"), position: LatLng(0,0));
  Marker gidilecek_durak_marker = Marker(markerId: MarkerId("hedef_marker"), position: LatLng(0,0));

  var gidilecek_yol = [];
  double hedefe_mesafe = 0;

  Position kullanici_mevcut_konum = new Position( longitude: 0,
                                                  latitude: 0,
                                                  timestamp: DateTime(0),
                                                  accuracy: 0,
                                                  altitude: 0,
                                                  heading: 0,
                                                  speed: 0,
                                                  speedAccuracy: 0);

  bool bildirim_olusturuldu_mu = false;

  void Mevcut_Konumu_Haritada_Ortala()
  {
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best, forceAndroidLocationManager: true)
        .then((Position pos) => {
          this.setState(() {
            kullanici_mevcut_konum = pos;

            harita_kontrolcusu.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                    target: LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude),
                    zoom: 12)
              )
            );

            /*BitmapDescriptor.fromAssetImage(
              ImageConfiguration(size: Size(24, 24)),
              "assets/kullanici_icon.png")
                .then((value) => this.setState(() {
                  kullanici_marker =
                      Marker( markerId: MarkerId("kullanici_marker"),
                              position: LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude),
                              icon: value
                      );
                })
            );*/

          kullanici_marker =
          Marker( markerId: MarkerId("kullanici_marker"),
                  position: LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
          );

          })
        }).catchError( (e) {
          print(e);
    });
  }

  Future<void> Firebase_Baslat()
  async
  {
    this.fb_app = await Firebase.
    initializeApp(options: Globals.api_cred);

  }

  void Tum_Firebase_Verisini_Cek()
  {
    final DatabaseReference db = FirebaseDatabase(app: this.fb_app).reference();
    db.child('/').once().
    then((result) =>
    {
      this.setState(()
      {
        istanbul_tum_hatlar = result.value;
        renderlanacak_hat_list = result.value;
        renderlanacak_durak_list = result.value[secili_hat_idx]['G'];
        lokal_db.Hat_Durak_Bilgilerini_Lokale_Yaz(json.encode(istanbul_tum_hatlar));
      })
    } ).
    catchError((e) =>
    {
      print("firebase_veri_okuma_hatasi")
    });
  }

  void Hat_ve_Durak_Verisini_Hazirla()
  {
    //!< Once hat ve durak bilgisini okumaya calisalim
    lokal_db.Hat_Durak_Bilgilerini_Lokalden_Oku()
      .then((value) => {
        Lokal_Okuma_Sonrasi_Islemleri_Yap(value)
      });
  }

  void Lokal_Okuma_Sonrasi_Islemleri_Yap(String lokal_okuma_sonucu_str)
  {
    //!< Eger dosyayi basariyla okuyamadiysak firebaseden cekelim
    if(lokal_okuma_sonucu_str == "okuma_hatasi")
    {
      Tum_Firebase_Verisini_Cek();
    }
    //!< Hatasiz donus olduysa dosyadan okuyabildik diye kabul ediyoruz.
    else
    {
      this.setState(() {
        final lokal_okuma_sonucu_json = json.decode(lokal_okuma_sonucu_str);

        istanbul_tum_hatlar = lokal_okuma_sonucu_json;

        renderlanacak_hat_list = lokal_okuma_sonucu_json;
        renderlanacak_durak_list = lokal_okuma_sonucu_json[secili_hat_idx]['G'];
      });
    }
  }

  @override
  void initState() {
    Firebase_Baslat();
    Hat_ve_Durak_Verisini_Hazirla();
    super.initState();

    Workmanager().initialize( (){
      Workmanager().executeTask((taskName, inputData) async {

        //!< Eger bir bildirim varsa
        if(true == bildirim_olusturuldu_mu)
        {
          //!< Once mevcut konumumuzu haritada ortalayalim
          Mevcut_Konumu_Haritada_Ortala();

          //!< Ardindan kamerayi uygun sekilde hareket ettirelim
          //!< Secili durak enlem ve boylam
          double hedef_enlem  = double.parse( this.renderlanacak_durak_list[this.secili_durak_idx]['y_coord'] );
          double hedef_boylam = double.parse( this.renderlanacak_durak_list[this.secili_durak_idx]['x_coord'] );

          //!< Kamerayi uygun yere alalim
          double orta_enlem    = (this.kullanici_mevcut_konum.latitude  + hedef_enlem ) / 2;
          double orta_boylam   = (this.kullanici_mevcut_konum.longitude + hedef_boylam) / 2;
          Iki_Nokta_Arasi_Mesafe_Hesapla( this.kullanici_mevcut_konum.latitude  ,
                                          this.kullanici_mevcut_konum.longitude ,
                                          hedef_enlem                           ,
                                          hedef_boylam                          )
           .then((hedefe_mesafe) => {
            this.setState(() {
              this.hedefe_mesafe = hedefe_mesafe;

              harita_kontrolcusu.animateCamera(
                  CameraUpdate.newCameraPosition(
                      CameraPosition(
                          target: LatLng(orta_enlem, orta_boylam),
                          zoom: Mesafeden_Harita_Zoom_Lv_Hesapla(hedefe_mesafe * 7/10)
                      )
                  )
              );


              //!< Eger ki hedefe mesafe belli degerden az ise alarm çaldıralım
              if(hedefe_mesafe < 200)
              {
                

                //!< Dalgayi durduralim
                Workmanager().cancelAll();
              }
            })
          });
        }

        return Future.value(true);
      });
    });
    Workmanager().registerPeriodicTask(
      "uniqueName", "taskName",
      frequency: Duration(seconds: 30),
    );
  }

  void Durak_Arama_Bari_Texti_ve_Listeyi_Degistir(String deger_str)
  {
    //!< Eger ki deger bossa
    if(deger_str == "")
    {
      //!< Tum listeyi setleyelim
      this.setState(() {
        renderlanacak_durak_list = istanbul_tum_hatlar[this.secili_hat_idx]['G'];
      });
    }
    //!< Bos degilse filtreleme yapalim
    else
    {
      var durak_list_tmp = [];

      //!< Listedeki her bir eleman icin
      for(int i = 0; i < this.istanbul_tum_hatlar.length; i++)
      {
        try
        {
          bool isim_texti_iceriyor_mu = this.istanbul_tum_hatlar[this.secili_hat_idx]['G'][i]['durak_adi'].toString().toLowerCase().contains(deger_str.toLowerCase());

          if(isim_texti_iceriyor_mu)
          {
            durak_list_tmp.add(this.istanbul_tum_hatlar[this.secili_hat_idx]['G'][i]);
          }
        }
        catch(e) {}
      }

      this.setState(() {

        renderlanacak_durak_list = durak_list_tmp;
      });
    }
  }

  void Hat_Arama_Bari_Texti_ve_Listeyi_Degistir(String deger_str)
  {
    //!< Oncelikle hat isminde bi degisim olduysa duragi da sifirlayalim
    this.setState(() {
      renderlanacak_durak_list = [];
      durak_arama_edit_text_aktiflik  = false;
      durak_arama_edit_text_deger = "";
      durak_arama_controller.clear();

      hat_arama_edit_text_deger = deger_str;
    });

    //!< Eger ki deger bossa
    if(deger_str == "")
    {
      //!< Dropdown visibilitysini kapat
      this.setState(() {
        hat_arama_dropdown_visibility = false;
      });
    }
    //!< Bos degilse filtreleme yapalim
    else
    {
      var hat_list_tmp = [];

      //!< Listedeki her bir eleman icin
      for(int i = 0; i < this.istanbul_tum_hatlar.length; i++)
      {
        try{
          String hat_adi_str = this.istanbul_tum_hatlar[i]["hat_adi"];
          bool isim_texti_iceriyor_mu    = hat_adi_str.toLowerCase().contains(deger_str.toLowerCase());

          if(isim_texti_iceriyor_mu)
          {
            hat_list_tmp.add(this.istanbul_tum_hatlar[i]);
          }
        }
        catch(e){}
      }

      this.setState(() {
        hat_arama_dropdown_visibility = true;

        renderlanacak_hat_list = hat_list_tmp;

        renderlanacak_durak_list = hat_list_tmp[this.secili_hat_idx]['G'];

        if(renderlanacak_hat_list.length <= secili_hat_idx)
        {
          secili_hat_idx = renderlanacak_hat_list.length - 1;
        }
      });
    }
  }

  deg2rad(deg) {
    const double pi = 3.1415926535897932;
    return deg * ( pi/180);
  }

  Future<double> Iki_Nokta_Arasi_Mesafe_Hesapla(double nokta_1_enlem  ,
                                                double nokta_1_boylam ,
                                                double nokta_2_enlem  ,
                                                double nokta_2_boylam ) async
  {
    var R = 6371; // Radius of the earth in km
    var dLat = deg2rad(nokta_2_enlem-nokta_1_enlem);  // deg2rad below
    var dLon = deg2rad(nokta_2_boylam-nokta_1_boylam);
    var a =
        sin(dLat/2) * sin(dLat/2) +
            cos(deg2rad(nokta_1_enlem)) * cos(deg2rad(nokta_2_enlem)) *
                sin(dLon/2) * sin(dLon/2)
    ;
    var c = 2 * atan2(sqrt(a), sqrt(1-a));
    var d = R * c; // Distance in km
    //!< Uzakligi metre cinsinden dondurelim
    return d * 1000;
  }

  double Mesafeden_Harita_Zoom_Lv_Hesapla(double mesafe)
  {
    double zoomLevel = 11;
    if (mesafe > 0) {
      double radiusElevated = mesafe + mesafe / 2;
      double scale = radiusElevated / 500;
      zoomLevel = 16 - log(scale) / log(2);
    }
    if(zoomLevel > 16) return 16;
    return zoomLevel;
  }

  void Bildirimi_Olustur()
  {
    this.setState(() {
      //!< Once paneli kapatalim ve bildirim var bayragini cekelim
      acilir_panel_kontroller.close();

      //!< Surekli olarak mesafeyi kontrol edecek ve gerektiğinde alarm
      //!< calacak olan taski kuralim
      bildirim_olusturuldu_mu = true;
    });

    //!< Secili durak enlem ve boylam
    double hedef_enlem  = double.parse( this.renderlanacak_durak_list[this.secili_durak_idx]['y_coord'] );
    double hedef_boylam = double.parse( this.renderlanacak_durak_list[this.secili_durak_idx]['x_coord'] );

    this.setState(() {
      //!< Hedef pinini olusturalim
      gidilecek_durak_marker =
      Marker( markerId: MarkerId("hedef_marker"),
          position: LatLng(hedef_enlem, hedef_boylam),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)
      );

      /*gidilecek_yol.add(
          Polyline(
            polylineId: PolylineId("line"),
            color: Colors.lightBlue,
            points:
              [LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude),
               LatLng(hedef_enlem, hedef_boylam)],
            width: 2
          )
      );*/

      //!< Kamerayi uygun yere alalim
      double orta_enlem    = (this.kullanici_mevcut_konum.latitude  + hedef_enlem ) / 2;
      double orta_boylam   = (this.kullanici_mevcut_konum.longitude + hedef_boylam) / 2;
      Iki_Nokta_Arasi_Mesafe_Hesapla( this.kullanici_mevcut_konum.latitude  ,
                                      this.kullanici_mevcut_konum.longitude ,
                                      hedef_enlem                           ,
                                      hedef_boylam                          )
      .then((hedefe_mesafe) => {
        this.setState(() {
          this.hedefe_mesafe = hedefe_mesafe;
          /*LatLngBounds bound;
          if(this.kullanici_mevcut_konum.latitude <= hedef_enlem)
          {
            bound = LatLngBounds(southwest: LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude),
                                 northeast: LatLng(hedef_enlem, hedef_boylam));
          }
          else
          {
            bound = LatLngBounds(southwest: LatLng(hedef_enlem, hedef_boylam),
                                 northeast: LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude));
          }

          CameraUpdate u2 = CameraUpdate.newLatLngBounds(bound, 24);
          this.harita_kontrolcusu.animateCamera(u2);*/

          harita_kontrolcusu.animateCamera(
              CameraUpdate.newCameraPosition(
                  CameraPosition(
                      target: LatLng(orta_enlem, orta_boylam),
                      zoom: Mesafeden_Harita_Zoom_Lv_Hesapla(hedefe_mesafe * 7/10)
                  )
              )
          );
        })
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SlidingUpPanel(
      controller: this.acilir_panel_kontroller,
      maxHeight: 80/100 * MediaQuery.of(context).size.height,
      minHeight: 44,
      borderRadius:
      BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24)
      ),

      //!< Swipe panel ici
      panel: Card(
        color: Colors.transparent,
        elevation: 0,
        child:
        Column(
          children: [

            //!< Mavi oval sey
            GestureDetector(
              onTap: () {
                this.setState(() {
                  if(acilir_panel_kontroller.isPanelOpen)
                  {
                    acilir_panel_kontroller.close();
                  }
                  else
                  {
                    acilir_panel_kontroller.open();
                  }
                });
              },
              child:
              Container(
                decoration:
                BoxDecoration(
                    color: Colors.blue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8)
                ),
                width: 52,
                height: 6,
                margin: EdgeInsets.only(top: 8),
              ),
            ),

            //!< Bildirim olustur texti
            Container(
              margin: EdgeInsets.only(left: 12, right: 12, top: 12),
              child:
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    "Yeni Bildirim Oluştur",
                    style:
                    TextStyle(
                      color: Colors.lightBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            //!< Hat ara
            Container(
                margin: EdgeInsets.only(left: 8, right: 8, top: 8),
                child:
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      width: 85/100 * MediaQuery.of(context).size.width,
                      height: 32,
                      child:
                      TextFormField(
                        onChanged: (deger_str) => Hat_Arama_Bari_Texti_ve_Listeyi_Degistir(deger_str),
                        decoration: InputDecoration(
                          alignLabelWithHint: true,
                          hintText: "Hat Ara",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        ),
                      ),
                    ),
                    Icon(Icons.search, color: Colors.lightBlue.withOpacity(0.8))
                  ],
                )
            ),

            //!< Hatlar dizisi
            if(renderlanacak_hat_list.length > 0)
            Container(
              height: 50,
              child: Flex(
                direction: Axis.vertical,
                children: [
                  Expanded(
                    child:
                    ListView.builder(
                        itemCount: renderlanacak_hat_list.length,
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        itemBuilder: (BuildContext context, int i) {
                          return GestureDetector(
                            onTap: () {
                              this.setState(() {
                                secili_hat_idx = i;
                                renderlanacak_durak_list = renderlanacak_hat_list[i]['G'];
                              });
                            },
                            child:
                            Container(
                              width: 54,
                              padding: EdgeInsets.symmetric(vertical: 0, horizontal: 4),
                              child: Card(
                                  color: this.secili_hat_idx != i ? Colors.white : Colors.lightBlue,
                                  elevation: 4,
                                  margin: EdgeInsets.fromLTRB(0, 8, 0, 8),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        this.renderlanacak_hat_list[i]['hat_adi'],
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: this.secili_hat_idx != i ? Colors.lightBlue: Colors.white,
                                        ),
                                      ),
                                    ],
                                  )
                              ),
                            ),
                          );
                        }
                    ),
                  )
                ],
              ),
            ),

            //!< Durak ara
            Container(
                margin: EdgeInsets.only(left: 8, right: 8, top: 12),
                child:
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      width: 85/100 * MediaQuery.of(context).size.width,
                      height: 32,
                      child:
                      TextFormField(
                        controller: this.durak_arama_controller,
                        onChanged: (deger_str) => Durak_Arama_Bari_Texti_ve_Listeyi_Degistir(deger_str),
                        decoration: InputDecoration(
                          alignLabelWithHint: true,
                          hintText: "Durak Seç",
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20)
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        ),
                      ),
                    ),
                    Icon(Icons.search, color: Colors.lightBlue.withOpacity(0.8))
                  ],
                )
            ),

            //!< Duraklar dizisi
            if(renderlanacak_durak_list.length > 0)
            Container(
              height: 120,
              child: Flex(
                direction: Axis.vertical,
                children: [
                  Expanded(
                    child:
                    ListView.builder(
                        itemCount: renderlanacak_durak_list.length,
                        scrollDirection: Axis.vertical,
                        shrinkWrap: true,
                        itemBuilder: (BuildContext context, int i) {
                          return GestureDetector(
                            onTap: () {
                              this.setState(() {
                                secili_durak_idx = i;
                              });
                            },
                            child: Container(
                              width: 42,
                              padding: EdgeInsets.symmetric(vertical: 0, horizontal: 4),
                              child: Card(
                                color: this.secili_durak_idx != i ? Colors.white: Colors.lightBlue,
                                elevation: 1,
                                child: Text(
                                  this.renderlanacak_durak_list[i]['durak_adi'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: this.secili_durak_idx != i ? Colors.lightBlue: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                    ),
                  )
                ],
              ),
            ),

            //!< Bildirim Olusturma butonu
            Card(
              margin: EdgeInsets.only(top: 8),
              elevation: 0,
              color: Colors.transparent,
              child:
              ElevatedButton(
                style:
                ButtonStyle(

                ),
                onPressed: Bildirimi_Olustur,
                child:
                Container(
                  alignment: Alignment.center,
                  width: MediaQuery.of(context).size.width * 8/10,
                  child:
                  Text(
                    "Alarm Kur",
                  ),
                )
              ),
            )
          ],
        ),
      ),

      //!< Arkaplan
      body: Container(
        color: Colors.white,
        child:
        GoogleMap(
          markers: {
            this.kullanici_marker,

            //!< Eger gidilecek durak secildiyse onu da marklayalim
            if(this.gidilecek_durak_marker.position.latitude != 0) this.gidilecek_durak_marker
          },
          /*polylines: {
            //!< Eger gidilecek durak secildiyse onu da marklayalim
            if(this.gidilecek_durak_marker.position.latitude != 0 && gidilecek_yol.length > 0) gidilecek_yol[0]
          },*/
          onMapCreated: (controller) => this.setState(() {
            harita_kontrolcusu = controller;
            Mevcut_Konumu_Haritada_Ortala();
          }),
          initialCameraPosition:
          CameraPosition(
              target:
              //this.kullanici_mevcut_konum.latitude != 0 ?
              //LatLng(this.kullanici_mevcut_konum.latitude, this.kullanici_mevcut_konum.longitude):
              LatLng(41.0082,28.9784),

              zoom:
              //this.kullanici_mevcut_konum.latitude != 0 ?
              //12 :
              10,
          ),
        ),
      ),
    );
  }
}

