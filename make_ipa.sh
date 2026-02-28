APP_FILE="$HOME/Library/Developer/Xcode/DerivedData/Limit-bgdcyklucytjrgfbxsppyjzbkbkj/Build/Products/Debug-iphoneos/Limit.app"

mkdir Payload
cp -r $APP_FILE Payload/
zip -r Limit.ipa Payload
rm -rf Payload

aws s3 cp ./Limit.ipa s3://stdg-exchange/Limit.ipa

#rm Limit.ipa
