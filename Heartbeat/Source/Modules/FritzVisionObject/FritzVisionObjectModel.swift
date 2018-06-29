//
//  FritzVisionObject.swift
//  Heartbeat
//
//  Created by Christopher Kelly on 6/29/18.
//  Copyright © 2018 Fritz Labs, Inc. All rights reserved.
//

import Foundation
import Vision
import AVFoundation
import FritzVision

public typealias FritzVisionObjectCallback = ([FritzVisionObject]?, Error?) -> Void


public class FritzVisionObject {
    let label: FritzVisionLabel
    let boundingBox: BoundingBox2

    init(label: FritzVisionLabel, boundingBox: BoundingBox2) {
        self.label = label
        self.boundingBox = boundingBox
    }
}

class FritzVisionObjectModel {

    let model = ssdlite_mobilenet_v2_coco().model
    let ssdPostProcessor = SSDPostProcessor(numAnchors: 1917, numClasses: 90)
    let semaphore = DispatchSemaphore(value: 1)

    let visionModel: VNCoreMLModel
    init() {
        guard let visionModel = try? VNCoreMLModel(for: model)
            else { fatalError("Can't load VisionML model") }
        self.visionModel = visionModel
    }

    func processClassifications(for request: VNRequest, error: Error?) -> [Prediction]? {
        guard let results = request.results as? [VNCoreMLFeatureValueObservation] else {
            return nil
        }
        guard results.count == 2 else {
            return nil
        }
        guard let boxPredictions = results[1].featureValue.multiArrayValue,
            let classPredictions = results[0].featureValue.multiArrayValue else {
                return nil
        }

        let predictions = self.ssdPostProcessor.postprocess(boxPredictions: boxPredictions, classPredictions: classPredictions)
        return predictions
    }

    func predict(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, options: [VNImageOption : Any], completion: @escaping FritzVisionObjectCallback) {

        let trackingRequest = VNCoreMLRequest(model: visionModel) { (request, error) in
            guard let predictions = self.processClassifications(for: request, error: error) else {
                completion(nil, error)
                return

            }
            let fritzObjects: [FritzVisionObject] = predictions.map { value in
                FritzVisionObject(label: FritzVisionLabel(label: value.detectedClassLabel!, confidence: value.score), boundingBox: value.finalPrediction)
            }
            completion(fritzObjects, nil)

            self.semaphore.signal()
        }
        trackingRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop

        self.semaphore.wait()
        do {
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: options)
            try imageRequestHandler.perform([trackingRequest])
        } catch {
            print(error)
            self.semaphore.signal()
        }
    }

    enum EXIFOrientation : Int32 {
        case topLeft = 1
        case topRight
        case bottomRight
        case bottomLeft
        case leftTop
        case rightTop
        case rightBottom
        case leftBottom

        var isReflect:Bool {
            switch self {
            case .topLeft,.bottomRight,.rightTop,.leftBottom: return false
            default: return true
            }
        }
    }

    func compensatingEXIFOrientation(deviceOrientation:UIDeviceOrientation) -> EXIFOrientation
    {
        switch (deviceOrientation) {
        case (.landscapeRight): return .bottomRight
        case (.landscapeLeft): return .topLeft
        case (.portrait): return .rightTop
        case (.portraitUpsideDown): return .leftBottom

        case (.faceUp): return .rightTop
        case (.faceDown): return .rightTop
        case (_): fallthrough
        default:
            NSLog("Called in unrecognized orientation")
            return .rightTop
        }
    }


}
