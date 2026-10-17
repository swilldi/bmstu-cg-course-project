//
//  ParameretStore.swift
//  NortherLights
//
//  Created by Dmitriy on 20.09.2026.
//

import Foundation
import SwiftUI

@Observable
class ParameretStore {
    typealias LayersColor = (top: Color, middle: Color, bottom: Color)
    
    var topHeight: Int
    var bottomHeight: Int
    var length: Int
    var inventory: Int
    var seed: Int
    var colors: LayersColor
    var curtainsCounts: Int
    
    init(topHeight: Int, bottomHeight: Int, length: Int, inventory: Int, seed: Int, colors: LayersColor, curtainsCounts: Int) {
        self.topHeight = topHeight
        self.bottomHeight = bottomHeight
        self.length = length
        self.inventory = inventory
        self.seed = seed
        self.colors = colors
        self.curtainsCounts = curtainsCounts
    }
    
    init() {
        self.topHeight = 0
        self.bottomHeight = 0
        self.length = 0
        self.inventory = 0
        self.seed = 0
        self.colors = (Color.red, Color.red, Color.red)
        self.curtainsCounts = 0
    }
}
