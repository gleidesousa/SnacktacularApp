//
//  SpotDetailView.swift
//  SnacktacularUI
//
//  Created by Gleidson De Sousa on 3/28/23.
//

import SwiftUI
import MapKit
import FirebaseFirestoreSwift
import PhotosUI

struct SpotDetailView: View {
    enum ButtonPressed {
        case review, photo
    }
    
    struct Annotation: Identifiable {
        let id = UUID().uuidString
        var name: String
        var address: String
        var coordinate: CLLocationCoordinate2D
    }
    
    @EnvironmentObject var spotVM: SpotViewModel
    @EnvironmentObject var locationManager: LocationManager
    @FirestoreQuery(collectionPath: "spots") var reviews: [Review]
    @FirestoreQuery(collectionPath: "spots") var photos: [Photo]
    @State var spot: Spot
    @State var newPhoto = Photo()
    @State private var showPlaceLookupSheet = false
    @State private var showReviewViewSheet = false
    @State private var showPhotoViewSheet = false
    @State private var showSaveAlert = false
    @State private var showingAsSheet = false
    @State private var buttonPressed = ButtonPressed.review
    @State private var uiImageSelected = UIImage()
    @State private var mapRegion = MKCoordinateRegion()
    @State private var annotations: [Annotation] = []
    @State private var selectedPhoto: PhotosPickerItem?
    var avgRating: String {
        guard reviews.count != 0 else {
            return "-.-"
        }
        let averageValue = Double(reviews.reduce(0) {$0 + $1.rating}) / Double(reviews.count)
        return String(format: "%.1f", averageValue)
    }
    @Environment(\.dismiss) private var dismiss
    let regionSize = 500.0
    var previewRunning = false
    
    var body: some View {
        VStack {
            Group {
                TextField("Name", text: $spot.name)
                    .font(.title)
                TextField("Address", text: $spot.address)
                    .font(.title2)
            }
            .disabled(spot.id == nil ? false : true)
            .textFieldStyle(.roundedBorder)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.gray.opacity(0.5), lineWidth: spot.id == nil ? 2 : 0)
            }
            .padding(.horizontal)
            
            Map(coordinateRegion: $mapRegion, showsUserLocation: true, annotationItems: annotations) { annotation in
                MapMarker(coordinate: annotation.coordinate)
            }
            .onChange(of: spot) { _ in
                annotations = [Annotation(name: spot.name, address: spot.address, coordinate: spot.coordinate)]
                mapRegion.center = spot.coordinate
            }
            
            SpotDetailPhotosScrollView(photos: photos, spot: spot)
            
            HStack {
                Group {
                    Text("Avg. Rating:")
                        .font(.title2)
                        .bold()
                    Text(avgRating)
                        .font(.title)
                        .fontWeight(.black)
                        .foregroundColor(Color("SnackColor"))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                
                Spacer()
                
                Group {
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .automatic) {
                        Image(systemName: "photo")
                        Text("Photo")
                    }
                    .onChange(of: selectedPhoto) { newValue in
                        Task {
                            do {
                                if let data = try await newValue?.loadTransferable(type: Data.self) {
                                    if let uiImage = UIImage(data: data) {
                                        uiImageSelected = uiImage
                                        print("📸 Successfully selected image")
                                        newPhoto = Photo()
                                        buttonPressed = .photo
                                        if spot.id == nil {
                                            showSaveAlert.toggle()
                                        } else {
                                            showPhotoViewSheet.toggle()
                                        }
                                    }
                                }
                            } catch {
                                print("😡 ERROR: selecting image failed \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    Button(action: {
                        buttonPressed = .review
                        if spot.id == nil {
                            showSaveAlert.toggle()
                        } else {
                            showReviewViewSheet.toggle()
                        }
                    }, label: {
                        Image(systemName: "star.fill")
                        Text("Rate")
                    })
                }
                .font(Font.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .buttonStyle(.borderedProminent)
                .bold()
                .tint(Color("SnackColor"))
            }
            .padding(.horizontal)
            
            List {
                Section {
                    ForEach(reviews) { review in
                        NavigationLink {
                            ReviewView(spot: spot, review: review)
                        } label: {
                            SpotReviewRowView(review: review)
                        }
                        
                    }
                }
            }
            .listStyle(.plain)
            
            Spacer()
        }
        .onAppear {
            if !previewRunning && spot.id != nil {
                $reviews.path = "spots/\(spot.id ?? "")/reviews"
                print("reviews.path = \($reviews.path)")
                
                $photos.path = "spots/\(spot.id ?? "")/photos"
                print("photos.path = \($photos.path)")
            } else {
                showingAsSheet = true
            }
            
            if spot.id != nil {
                mapRegion = MKCoordinateRegion(center: spot.coordinate, latitudinalMeters: regionSize, longitudinalMeters: regionSize)
            } else {
                Task {
                    mapRegion = MKCoordinateRegion(center: locationManager.location?.coordinate ?? CLLocationCoordinate2D(), latitudinalMeters: regionSize, longitudinalMeters: regionSize)
                }
                
            }
            annotations = [Annotation(name: spot.name, address: spot.address, coordinate: spot.coordinate)]
            
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(spot.id == nil)
        .toolbar {
            if showingAsSheet {
                if spot.id == nil && showingAsSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            Task {
                                let success = await spotVM.saveSpot(spot: spot)
                                if success {
                                    dismiss()
                                } else {
                                    print("😡 DANG! Error saving spot!")
                                }
                            }
                            dismiss()
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Spacer()
                        
                        Button {
                            showPlaceLookupSheet.toggle()
                        } label: {
                            Image(systemName: "magnifyingglass")
                            Text("Lookup Place")
                        }
                        
                    }
                } else if showingAsSheet && spot.id != nil {
                    ToolbarItem(placement: .navigationBarTrailing){
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPlaceLookupSheet) {
            PlaceLookupView(spot: $spot)
        }
        .sheet(isPresented: $showReviewViewSheet) {
            NavigationStack {
                ReviewView(spot: spot, review: Review())
            }
        }
        .sheet(isPresented: $showPhotoViewSheet) {
            NavigationStack {
                PhotoView(photo: $newPhoto, uiImage: uiImageSelected, spot: spot)
            }
        }
        .alert("Cannot Rate Place Unless It is Saved", isPresented: $showSaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Save", role: .none) {
                Task {
                    let success = await spotVM.saveSpot(spot: spot)
                    spot = spotVM.spot
                    if success {
                        $reviews.path = "spots/\(spot.id ?? "")/reviews"
                        $photos.path = "spots/\(spot.id ?? "")/photos"
                        switch buttonPressed {
                        case .review:
                            showReviewViewSheet.toggle()
                        case .photo:
                            showPhotoViewSheet.toggle()
                        }
                    } else {
                        print("😡 Dang! Error saving spot!")
                    }
                }
            }
        } message: {
            Text("Would you like to save this alert first so that you can enter a review?")
        }
    }
}

struct SpotDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SpotDetailView(spot: Spot(), previewRunning: true)
                .environmentObject(SpotViewModel())
                .environmentObject(LocationManager())
        }
    }
}
